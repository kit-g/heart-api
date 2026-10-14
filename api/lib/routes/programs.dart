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
