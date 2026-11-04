import 'package:heart/globals/globals.dart';
import 'package:heart/inputs/inputs.dart';
import 'package:heart/middleware/database.dart';
import 'package:heart/models/errors.dart';
import 'package:heart/models/pagination.dart';
import 'package:heart/models/program_copy.dart';
import 'package:heart_models/heart_models.dart';
import 'package:relic/relic.dart';

Future<CoachProgram> saveCoachProgram(Request req) async {
  final input = await CoachProgramIn.fromRequest(req, id: req.rawPathParameters[#programId]!);
  return req.coachLibraryService.saveCoachProgram(
    coachId: req.userId,
    id: input.id,
    name: input.name,
    body: input.body,
  );
}

Future<Paginated<CoachProgram>> getCoachPrograms(Request req) async {
  final query = PageQuery.fromRequest(req);
  final page = await req.coachLibraryService.getCoachPrograms(
    coachId: req.userId,
    cursor: query.cursor,
    limit: query.limit,
  );
  return Paginated<CoachProgram>.from(page, itemsKey: 'programs', cursorOf: (program) => program.id);
}

Future<CoachProgram> getCoachProgram(Request req) {
  return req.coachLibraryService.getCoachProgram(coachId: req.userId, id: req.rawPathParameters[#programId]!);
}

Future<Model> deleteCoachProgram(Request req) async {
  await req.coachLibraryService.deleteCoachProgram(coachId: req.userId, id: req.rawPathParameters[#programId]!);
  throw const NoContent();
}

Future<CoachProgramHolders> getCoachProgramHolders(Request req) async {
  return CoachProgramHolders(
    await req.coachLibraryService.getCoachProgramHolders(
      coachId: req.userId,
      id: req.rawPathParameters[#programId]!,
    ),
  );
}

Future<ProgramDeliveries> sendCoachProgram(Request req) async {
  final input = await CoachProgramSendIn.fromRequest(req);
  final id = req.rawPathParameters[#programId]!;
  return ProgramDeliveries([
    for (final connectionId in input.connectionIds)
      await deliverCoachProgram(req, coachId: req.userId, id: id, connectionId: connectionId),
  ]);
}

/// Makes the student's own copy, on the server since they may be offline. What
/// they already hold answers that copy. Someone they aren't coaching, or a limit of
/// theirs, comes back as not delivered: a send covers several clients, and one that
/// can't get it shouldn't stop the rest or hide who already did.
Future<ProgramDelivery> deliverCoachProgram(
  Request req, {
  required String coachId,
  required String id,
  required String connectionId,
}) async {
  final context = await req.coachLibraryService.getCoachSendContext(
    coachId: coachId,
    id: id,
    connectionId: connectionId,
  );
  if (context == null) throw NotFound(type: 'Library program', id: id);
  final studentId = context.studentId;
  if (studentId == null) {
    return ProgramDelivery(connectionId: connectionId, delivered: false, reason: 'not_coaching');
  }
  if (context.existingProgramId case final String existing) {
    return ProgramDelivery(connectionId: connectionId, delivered: true, programId: existing);
  }

  final body = context.body;
  final ids = copyIds(
    body,
    exercises: await req.coachLibraryService.matchExercisesForStudent(
      ids: idsIn(body).toList(),
      coachId: coachId,
      studentId: studentId,
    ),
  );
  final input = ProgramCreateIn.fromJson(studentId, (remapIds(body, ids)! as Map).cast<String, dynamic>());
  try {
    final (program, _) = await req.programService.createProgramOrExisting(
      userId: studentId,
      program: input.program,
      sessions: input.sessions,
      copy: (
        coachId: coachId,
        connectionId: connectionId,
        libraryProgramId: id,
        libraryVersion: context.version,
        libraryIds: ids,
        waits: context.studentBusy,
      ),
    );
    return ProgramDelivery(connectionId: connectionId, delivered: true, programId: program.id);
  } on BadRequest catch (error) {
    return ProgramDelivery(connectionId: connectionId, delivered: false, reason: error.code);
  }
}

Future<Model> startProgram(Request req) async {
  await req.coachLibraryService.startProgram(userId: req.userId, programId: req.rawPathParameters[#programId]!);
  throw const NoContent();
}
