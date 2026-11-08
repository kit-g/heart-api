import 'package:heart/globals/config.dart';
import 'package:heart/globals/globals.dart';
import 'package:heart/inputs/inputs.dart';
import 'package:heart/middleware/database.dart';
import 'package:heart/middleware/events.dart';
import 'package:heart/models/errors.dart';
import 'package:heart/models/pagination.dart';
import 'package:heart/models/program_copy.dart';
import 'package:heart/notifications/topics.dart';
import 'package:heart_models/heart_models.dart';
import 'package:logging/logging.dart' as logging;
import 'package:relic/relic.dart';

final _logger = logging.Logger('CoachLibrary');

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
  if (query.cursor case final cursor? when !isUuidV7(cursor)) {
    throw const BadRequest(reason: 'cursor must be the one the previous page returned');
  }
  final page = await req.coachLibraryService.getCoachPrograms(
    coachId: req.userId,
    cursor: query.cursor,
    limit: query.limit,
  );
  return Paginated<CoachProgram>.from(page, itemsKey: 'programs', cursorOf: (program) => program.id);
}

/// The library's path id, refused as missing before it reaches a `::uuid` cast: every
/// one was saved as a v7.
String libraryIdOf(Request req) {
  return switch (req.rawPathParameters[#programId]!) {
    final String id when isUuidV7(id) => id,
    final id => throw NotFound(type: 'Library program', id: id),
  };
}

Future<CoachProgram> getCoachProgram(Request req) {
  return req.coachLibraryService.getCoachProgram(coachId: req.userId, id: libraryIdOf(req));
}

Future<Model> deleteCoachProgram(Request req) async {
  await req.coachLibraryService.deleteCoachProgram(coachId: req.userId, id: libraryIdOf(req));
  throw const NoContent();
}

/// A program that isn't the coach's answers 404, as reading it does, rather than an
/// empty list.
Future<CoachProgramHolders> getCoachProgramHolders(Request req) async {
  final id = libraryIdOf(req);
  await req.coachLibraryService.getCoachProgram(coachId: req.userId, id: id);
  return CoachProgramHolders(await req.coachLibraryService.getCoachProgramHolders(coachId: req.userId, id: id));
}

Future<ProgramDeliveries> sendCoachProgram(Request req) async {
  final id = libraryIdOf(req);
  final input = await CoachProgramSendIn.fromRequest(req);
  return ProgramDeliveries([
    for (final connectionId in input.connectionIds)
      await deliverCoachProgram(req, coachId: req.userId, id: id, connectionId: connectionId, tellStudent: true),
  ]);
}

/// Makes the student's own copy, on the server since they may be offline. What
/// they already hold answers that copy. Someone they aren't coaching, or anything
/// about this one client that refuses it, comes back as not delivered: a send covers
/// several clients, and one that can't get it shouldn't stop the rest or hide who
/// already did.
Future<ProgramDelivery> deliverCoachProgram(
  Request req, {
  required String coachId,
  required String id,
  required String connectionId,
  bool tellStudent = false,
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

  try {
    final body = forCopy(context.body);
    final exercises = await req.coachLibraryService.matchExercisesForStudent(
      ids: idsIn(body).toList(),
      coachId: coachId,
      studentId: studentId,
    );
    final ids = copyIds(body, exercises: exercises);
    final input = ProgramCreateIn.fromJson(studentId, (remapIds(body, ids)! as Map).cast<String, dynamic>());
    // an exercise the coach no longer has, or never could pass on, would be dropped
    // from its session without a word
    final resolved = exercises.values.toSet();
    final missing = [
      for (final session in input.sessions)
        for (final exercise in session.exercises)
          if (!resolved.contains(exercise.exerciseId)) exercise.exerciseId,
    ];
    if (missing.isNotEmpty) {
      return ProgramDelivery(connectionId: connectionId, delivered: false, reason: 'unknown_exercise');
    }
    final (program, created) = await req.programService.createProgramOrExisting(
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
    if ((created && tellStudent, program.id) case (true, final String programId)) {
      await _tellStudent(req, studentId: studentId, programId: programId, connectionId: connectionId);
    }
    return ProgramDelivery(connectionId: connectionId, delivered: true, programId: program.id);
  } on Conflict {
    // another send made it first: what they hold now answers this one
    return deliverCoachProgram(req, coachId: coachId, id: id, connectionId: connectionId, tellStudent: tellStudent);
  } on ApiException catch (error) {
    return ProgramDelivery(connectionId: connectionId, delivered: false, reason: error.code);
  }
}

Future<Model> startProgram(Request req) async {
  final programId = req.rawPathParameters[#programId]!;
  if (!isUuidV7(programId)) throw NotFound(type: 'Program', id: programId, code: 'program_not_found');
  await req.coachLibraryService.startProgram(userId: req.userId, programId: programId);
  throw const NoContent();
}

/// The copy is theirs by now, and their app finds it on its next fetch anyway, so a
/// push that can't go out doesn't make a delivered program look undelivered.
Future<void> _tellStudent(
  Request req, {
  required String studentId,
  required String programId,
  required String connectionId,
}) async {
  try {
    await req.events.publish(
      queueUrl: req.config.eventsQueueUrl,
      message: {
        'type': 'push.requested',
        'userId': studentId,
        'topic': PushTopic.programReceived.key,
        'name': ?req.user.displayName,
        'actorId': req.userId,
        'connectionId': connectionId,
        'data': {'programId': programId},
      },
    );
  } catch (error, stack) {
    _logger.warning('could not tell $studentId of program $programId', error, stack);
  }
}
