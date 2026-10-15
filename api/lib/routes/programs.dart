import 'package:heart/core/handler.dart';
import 'package:heart/globals/globals.dart';
import 'package:heart/inputs/inputs.dart';
import 'package:heart/middleware/database.dart';
import 'package:heart/models/errors.dart';
import 'package:heart/models/programs.dart';
import 'package:heart_models/heart_models.dart';
import 'package:relic/relic.dart';

Future<ProgramsResponse> getMyPrograms(Request req) async {
  return ProgramsResponse(programs: await req.programService.getPrograms(req.userId));
}

Future<Program> getMyProgram(Request req) {
  return req.programService.getProgram(userId: req.userId, programId: req.rawPathParameters[#programId]!);
}

Future<Model> createProgram(Request req) async {
  final input = await ProgramCreateIn.fromRequest(req);
  final (program, isNew) = await req.programService.createProgramOrExisting(
    userId: req.userId,
    program: input.program,
    sessions: input.sessions,
  );
  if (isNew) return Created(program);
  return program;
}

Future<Program> updateProgram(Request req) {
  return updateProgramById(req, req.rawPathParameters[#programId]!);
}

Future<Program> updateProgramById(Request req, String programId) async {
  final input = await ProgramUpdateIn.fromRequest(req);
  return req.programService.updateProgram(userId: req.userId, programId: programId, program: input.program);
}

Future<Model> deleteProgram(Request req) {
  return deleteProgramById(req, req.rawPathParameters[#programId]!);
}

Future<Model> deleteProgramById(Request req, String programId) async {
  await req.programService.deleteProgram(
    userId: req.userId,
    programId: programId,
    keepTemplates: ProgramDeleteQuery.fromRequest(req).keepTemplates,
  );
  throw const NoContent();
}

Future<ProgramActionsResponse> getProgramActions(Request req) async {
  final actions = await req.programService.getProgramActions(
    userId: req.userId,
    programId: req.rawPathParameters[#programId]!,
  );
  return ProgramActionsResponse(actions: actions);
}

Future<Model> createProgramAction(Request req) {
  return createProgramActionFor(req, req.rawPathParameters[#programId]!);
}

Future<Model> createProgramActionFor(Request req, String programId) async {
  final input = await ProgramActionIn.fromRequest(req);
  final (action, isNew) = await req.programService.createProgramAction(
    userId: req.userId,
    programId: programId,
    action: input.action,
  );
  if (isNew) return Created(action);
  return action;
}

Future<Model> deleteProgramAction(Request req) async {
  await req.programService.deleteProgramAction(
    userId: req.userId,
    programId: req.rawPathParameters[#programId]!,
    actionId: req.rawPathParameters[#actionId]!,
  );
  throw const NoContent();
}

Future<ProgramBasesResponse> getProgramBases(Request req) async {
  final bases = await req.programService.getProgramBases(
    userId: req.userId,
    programId: req.rawPathParameters[#programId]!,
  );
  return ProgramBasesResponse(bases: bases);
}

Future<Model> createProgramBase(Request req) {
  return createProgramBaseFor(req, req.rawPathParameters[#programId]!);
}

Future<Model> createProgramBaseFor(Request req, String programId) async {
  final input = await ProgramBaseIn.fromRequest(req);
  final (base, isNew) = await req.programService.createProgramBase(
    userId: req.userId,
    programId: programId,
    base: input.base,
  );
  if (isNew) return Created(base);
  return base;
}

Future<Model> deleteProgramBase(Request req) async {
  await req.programService.deleteProgramBase(
    userId: req.userId,
    programId: req.rawPathParameters[#programId]!,
    baseId: req.rawPathParameters[#baseId]!,
  );
  throw const NoContent();
}

/// Where the user stands in [program], and each exercise's current base and
/// stage, read off its history the way the app reads it. The server's weeks
/// are ISO weeks in UTC: it knows neither the user's zone nor their first
/// weekday.
Future<ProgramState> programState(Request req, Program program, {bool withBases = false}) async {
  final service = req.programService;
  final programId = program.id!;
  final (marks, actions, bases) = await (
    service.getProgramMarks(userId: req.userId, programId: programId),
    service.getProgramActions(userId: req.userId, programId: programId),
    switch (withBases) {
      true => service.getProgramBases(userId: req.userId, programId: programId),
      false => Future.value(const <ProgramBase>[]),
    },
  ).wait;
  return (
    position: ProgramPosition.of(program, marks: marks, actions: actions, now: DateTime.timestamp()),
    bases: currentBases(bases),
    stages: currentStages(actions),
  );
}

/// Where the user stands in a program: its position, and the current base and
/// stage of each exercise, or slot that has its own, as `currentBases` and
/// `currentStages` key them.
typedef ProgramState = ({
  ProgramPosition position,
  Map<String, ProgramBase> bases,
  Map<String, int> stages,
});

/// [program]'s history: its bases with their causes, its actions and its
/// skips (heart-api#260).
Future<ProgramHistory> programHistory(Request req, Program program) async {
  final service = req.programService;
  final programId = program.id!;
  final (bases, actions, skips, sessions) = await (
    service.getProgramBases(userId: req.userId, programId: programId),
    service.getProgramActions(userId: req.userId, programId: programId),
    service.getProgramSkips(userId: req.userId, programId: programId),
    service.getProgramWorkouts(userId: req.userId, programId: programId),
  ).wait;
  return ProgramHistory(
    bases: bases,
    actions: actions,
    skips: skips,
    tests: program.tests.keys.toSet(),
    sessions: sessions,
  );
}

/// The session [state] puts next, planned from its bases and stages; null when
/// there is none, or its template is gone. [templates] spares a read when the caller
/// has them already.
Future<PlannedSession?> nextSession(
  Request req,
  Program program,
  ProgramState state, {
  Iterable<Template>? templates,
}) async {
  final next = state.position.next;
  if (next == null) return null;
  final Template? session = switch (templates) {
    final Iterable<Template> templates => templates.where((template) => template.id == next).firstOrNull,
    null =>
      await req.templatesService
          .getTemplate(userId: req.userId, templateId: next)
          .then<Template?>((template) => template, onError: (_) => null),
  };
  if (session == null) return null;
  return PlannedSession.of(program, session, position: state.position, bases: state.bases, stages: state.stages);
}

/// [program]'s session templates in its order, null for one that is gone.
Future<List<Template?>> programSessions(Request req, Program program) {
  return Future.wait([
    for (final session in program.sessions)
      req.templatesService
          .getTemplate(userId: req.userId, templateId: session)
          .then<Template?>((template) => template, onError: (_) => null),
  ]);
}
