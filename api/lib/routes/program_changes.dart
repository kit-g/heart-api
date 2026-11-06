import 'package:heart/core/handler.dart';
import 'package:heart/core/request.dart';
import 'package:heart/globals/config.dart';
import 'package:heart/globals/globals.dart';
import 'package:heart/inputs/inputs.dart';
import 'package:heart/middleware/database.dart';
import 'package:heart/middleware/events.dart';
import 'package:heart/models/errors.dart';
import 'package:heart/models/program_copy.dart';
import 'package:heart/models/programs.dart';
import 'package:heart/models/workouts.dart';
import 'package:heart/notifications/topics.dart';
import 'package:heart/routes/programs.dart';
import 'package:heart_models/heart_models.dart';
import 'package:relic/relic.dart';

/// A silent push: the other side's app fetches what changed.
Future<void> tellOtherSide(Request req, String programId) async {
  final other = await req.programChangeService.otherSideOf(actorId: req.userId, programId: programId);
  if (other == null) return;
  await req.events.publish(
    queueUrl: req.config.eventsQueueUrl,
    message: {
      'type': 'push.requested',
      'userId': other,
      'topic': PushTopic.programChanged.key,
      'actorId': req.userId,
      'data': {'programId': programId},
    },
  );
}

Future<ProgramChanges> getProgramChanges(Request req) async {
  return ProgramChanges(
    await req.programChangeService.getProgramChanges(
      ownerId: req.userId,
      programId: req.rawPathParameters[#programId]!,
      since: req.url.queryParameters['since'],
    ),
  );
}

Future<Model> revertProgramChange(Request req) {
  return revertById(
    req,
    ownerId: req.userId,
    programId: req.rawPathParameters[#programId]!,
    changeId: req.rawPathParameters[#changeId]!,
  );
}

/// Putting a change back is a new change, and it restores what the deletion of a
/// session cleared, so the student's position returns.
Future<Model> revertById(
  Request req, {
  required String ownerId,
  required String programId,
  required String changeId,
}) async {
  final service = req.programChangeService;
  final found = await service.getProgramChange(ownerId: ownerId, programId: programId, changeId: changeId);
  if (found == null) throw NotFound(type: 'Change', id: changeId);
  final (:change, :links) = found;

  switch ((change.sessionId, change.before)) {
    case (null, final Map<String, dynamic> before):
      await service.writeProgramFields(
        ownerId: ownerId,
        actorId: req.userId,
        programId: programId,
        program: ProgramUpdateIn.fromJson(before).program,
        baseRevision: change.revision,
        kind: 'revert',
      );
    case (final String sessionId, null):
      await service.removeSession(
        ownerId: ownerId,
        actorId: req.userId,
        sessionId: sessionId,
        programId: programId,
        kind: 'revert',
      );
    case (final String sessionId, final Map<String, dynamic> before):
      final written = await service.writeSession(
        ownerId: ownerId,
        actorId: req.userId,
        sessionId: sessionId,
        programId: programId,
        body: TemplateUpdateIn.fromJson(before, userId: ownerId).request,
        baseRevision: change.revision,
        kind: 'revert',
      );
      if (written == null) {
        await service.restoreSession(
          ownerId: ownerId,
          actorId: req.userId,
          programId: programId,
          body: TemplateCreateIn.fromJson(before, userId: ownerId).request,
          links: links,
          kind: 'revert',
        );
      }
    default:
      throw const BadRequest(reason: 'there is nothing to put back');
  }
  await tellOtherSide(req, programId);
  throw const NoContent();
}

Future<void> _assertCanRead(Request req, String student, String programId) async {
  final access = await req.programChangeService.getCopyAccess(
    coachId: req.userId,
    studentId: student,
    programId: programId,
  );
  if (!access.readable) throw const Forbidden(reason: 'You do not have permission to read this program.');
}

Future<void> _assertCanWrite(Request req, String student, String programId) async {
  final access = await req.programChangeService.getCopyAccess(
    coachId: req.userId,
    studentId: student,
    programId: programId,
  );
  if (!access.writable) throw const Forbidden(reason: 'You can no longer change this program.');
}

Future<ProgramsResponse> getCopies(Request req) async {
  return ProgramsResponse(
    programs: await req.programChangeService.getCopies(
      coachId: req.userId,
      studentId: req.rawPathParameters[#targetUserId]!,
    ),
  );
}

/// Worked out from what the coach can read, so a hidden workout leaves its session
/// undone here, and the week can trail the student's own.
Future<CoachProgramView> getCopy(Request req) async {
  final student = req.rawPathParameters[#targetUserId]!;
  final programId = req.rawPathParameters[#programId]!;
  await _assertCanRead(req, student, programId);

  final program = await req.programService.getProgram(userId: student, programId: programId);
  final (marks, actions) = await (
    req.programChangeService.getVisibleMarks(readerId: req.userId, ownerId: student, programId: programId),
    req.programService.getProgramActions(userId: student, programId: programId),
  ).wait;
  final sessions = await Future.wait(
    program.sessions.map((id) => req.templatesService.getTemplate(userId: student, templateId: id)),
  );
  return CoachProgramView(
    program: program,
    sessions: sessions,
    position: ProgramPosition.of(program, marks: marks, actions: actions, now: DateTime.timestamp()).toMap(),
  );
}

Future<ProgramChanges> getCopyChanges(Request req) async {
  final student = req.rawPathParameters[#targetUserId]!;
  final programId = req.rawPathParameters[#programId]!;
  await _assertCanRead(req, student, programId);
  return ProgramChanges(
    await req.programChangeService.getProgramChanges(
      ownerId: student,
      programId: programId,
      since: req.url.queryParameters['since'],
    ),
  );
}

Future<Program> updateCopy(Request req) async {
  final student = req.rawPathParameters[#targetUserId]!;
  final programId = req.rawPathParameters[#programId]!;
  await _assertCanWrite(req, student, programId);
  final input = await ProgramUpdateIn.fromRequest(req);
  final program = await req.programChangeService.writeProgramFields(
    ownerId: student,
    actorId: req.userId,
    programId: programId,
    program: input.program,
    baseRevision: input.baseRevision,
    changeId: input.changeId,
  );
  await tellOtherSide(req, programId);
  return program ?? (throw NotFound(type: 'Program', id: programId, code: 'program_not_found'));
}

Future<Template> updateCopySession(Request req) async {
  final student = req.rawPathParameters[#targetUserId]!;
  final programId = req.rawPathParameters[#programId]!;
  final sessionId = req.rawPathParameters[#sessionId]!;
  await _assertCanWrite(req, student, programId);
  final json = await req.json();
  final service = req.programChangeService;
  final input = TemplateUpdateIn.fromJson(json, userId: student);

  final session =
      await service.writeSession(
        ownerId: student,
        actorId: req.userId,
        sessionId: sessionId,
        programId: programId,
        body: input.request,
        baseRevision: input.baseRevision,
        changeId: input.changeId,
      ) ??
      await service.restoreSession(
        ownerId: student,
        actorId: req.userId,
        programId: programId,
        body: TemplateCreateIn.fromJson({...json, 'id': sessionId}, userId: student).request,
      );
  await tellOtherSide(req, programId);
  return session;
}

Future<Model> deleteCopySession(Request req) async {
  final student = req.rawPathParameters[#targetUserId]!;
  final programId = req.rawPathParameters[#programId]!;
  await _assertCanWrite(req, student, programId);
  final sessionId = req.rawPathParameters[#sessionId]!;
  final removed = await req.programChangeService.removeSession(
    ownerId: student,
    actorId: req.userId,
    sessionId: sessionId,
    programId: programId,
  );
  if (!removed) throw NotFound(type: 'Session', id: sessionId);
  await tellOtherSide(req, programId);
  throw const NoContent();
}

Future<Model> revertCopyChange(Request req) async {
  final student = req.rawPathParameters[#targetUserId]!;
  final programId = req.rawPathParameters[#programId]!;
  await _assertCanWrite(req, student, programId);
  return revertById(req, ownerId: student, programId: programId, changeId: req.rawPathParameters[#changeId]!);
}

/// `POST /library-programs/:id/update`: writes the current version through the copy's
/// id map, so a session the student already trained keeps its id, and with it their
/// week and bases. A recorded change, so it can be put back.
Future<ProgramDeliveries> updateCopies(Request req) async {
  final input = await CoachProgramSendIn.fromRequest(req);
  final id = req.rawPathParameters[#programId]!;
  return ProgramDeliveries([
    for (final connectionId in input.connectionIds) await updateCopyFor(req, id: id, connectionId: connectionId),
  ]);
}

Future<ProgramDelivery> updateCopyFor(Request req, {required String id, required String connectionId}) async {
  final library = req.coachLibraryService;
  final context = await library.getCoachSendContext(coachId: req.userId, id: id, connectionId: connectionId);
  if (context == null) throw NotFound(type: 'Library program', id: id);
  final student = context.studentId;
  if (student == null) {
    return ProgramDelivery(connectionId: connectionId, delivered: false, reason: 'not_coaching');
  }
  final programId = context.existingProgramId;
  if (programId == null) {
    return ProgramDelivery(connectionId: connectionId, delivered: false, reason: 'not_sent');
  }

  final changes = req.programChangeService;
  final body = context.body;
  final known = await changes.getCopyIds(ownerId: student, programId: programId);
  final ids = copyIds(
    body,
    exercises: await library.matchExercisesForStudent(
      ids: idsIn(body).toList(),
      coachId: req.userId,
      studentId: student,
    ),
    known: known,
  );
  final next = (remapIds(body, ids)! as Map).cast<String, dynamic>();
  final input = ProgramCreateIn.fromJson(student, next);

  final current = await req.programService.getProgram(userId: student, programId: programId);
  final wanted = {for (final session in input.sessions) ?session.id};

  await changes.writeProgramFields(
    ownerId: student,
    actorId: req.userId,
    programId: programId,
    program: ProgramUpdateIn.fromJson({...next, 'archived': current.archived}).program,
    baseRevision: 1 << 30,
    kind: 'library_update',
  );
  final sessions = (next['sessions'] as List?) ?? const [];
  for (final session in sessions.cast<Map>()) {
    final json = session.cast<String, dynamic>();
    final written = await changes.writeSession(
      ownerId: student,
      actorId: req.userId,
      sessionId: json['id'] as String,
      programId: programId,
      body: TemplateUpdateIn.fromJson(json, userId: student).request,
      baseRevision: 1 << 30,
      kind: 'library_update',
    );
    if (written == null) {
      await changes.restoreSession(
        ownerId: student,
        actorId: req.userId,
        programId: programId,
        body: TemplateCreateIn.fromJson(json, userId: student).request,
        kind: 'library_update',
      );
    }
  }
  for (final session in current.sessions.where((session) => !wanted.contains(session))) {
    await changes.removeSession(
      ownerId: student,
      actorId: req.userId,
      sessionId: session,
      programId: programId,
      kind: 'library_update',
    );
  }
  await changes.setCopyVersion(ownerId: student, programId: programId, version: context.version, ids: ids);
  await tellOtherSide(req, programId);
  return ProgramDelivery(connectionId: connectionId, delivered: true, programId: programId);
}

Future<void> _assertCanLog(Request req, String student) async {
  if (!await req.programChangeService.canLogFor(coachId: req.userId, studentId: student)) {
    throw const Forbidden(reason: 'You can only log for a client you are coaching.');
  }
}

/// A workout entered in person. It's the student's, and says who entered it. A
/// coach's custom exercise reaches the student as sending a program does, so nothing
/// is dropped. Moving a base is the device's job, as with any workout: it posts that
/// to the route below.
Future<Model> logWorkoutFor(Request req) => logWorkoutForStudent(req, req.rawPathParameters[#targetUserId]!);

Future<Model> logWorkoutForStudent(Request req, String student) async {
  await _assertCanLog(req, student);
  final json = (await WorkoutLogIn.fromRequest(req)).body;
  final exercises = await req.coachLibraryService.matchExercisesForStudent(
    ids: idsIn(json['exercises']).toList(),
    coachId: req.userId,
    studentId: student,
  );
  final body = (remapIds(json, exercises)! as Map).cast<String, dynamic>();

  final (workout, created) = await req.workoutsService.createWorkout(
    userId: student,
    body: WorkoutRequest(userId: student, body: body),
    imageUrl: req.config.cdnAssetUrl,
    loggedBy: req.userId,
  );
  if (created) return Created(workout);

  // An id already there is a retry only if this coach logged it, and what comes back is
  // what they can read. Anything else would turn this into a way to read any workout.
  if (workout.loggedBy != req.userId) {
    throw const Forbidden(code: 'id_taken', reason: 'this id belongs to something else');
  }
  return req.workoutsService.getTargetWorkout(
    requesterId: req.userId,
    targetUserId: student,
    workoutId: workout.id,
    imageUrl: req.config.cdnAssetUrl,
  );
}

/// The base a workout the coach logged moved, worked out on their device. The
/// student's app is told, so it plans from the new base.
Future<Model> moveBaseFor(Request req) async {
  final student = req.rawPathParameters[#targetUserId]!;
  final programId = req.rawPathParameters[#programId]!;
  await _assertCanWrite(req, student, programId);
  final base = await createProgramBaseFor(req, programId, userId: student, loggedBy: req.userId);
  await tellOtherSide(req, programId);
  return base;
}

Future<Model> savePlanFor(Request req) async {
  final student = req.rawPathParameters[#targetUserId]!;
  await _assertCanLog(req, student);
  final input = await WorkoutPlanIn.fromRequest(req);
  await req.programChangeService.savePlan(
    userId: student,
    workoutId: req.rawPathParameters[#workoutId]!,
    plan: input.plan,
    loggedBy: req.userId,
  );
  throw const NoContent();
}

Future<Model> saveWorkoutPlan(Request req) async {
  final input = await WorkoutPlanIn.fromRequest(req);
  await req.programChangeService.savePlan(
    userId: req.userId,
    workoutId: req.rawPathParameters[#workoutId]!,
    plan: input.plan,
  );
  throw const NoContent();
}

Future<WorkoutPlan> getTargetWorkoutPlan(Request req) async {
  final workoutId = req.rawPathParameters[#workoutId]!;
  final plan = await req.programChangeService.getPlan(
    readerId: req.userId,
    ownerId: req.rawPathParameters[#targetUserId]!,
    workoutId: workoutId,
  );
  return WorkoutPlan(plan ?? (throw NotFound(type: 'Plan', id: workoutId)));
}

// the plain routes ask this first: a session of a copy is recorded
Future<Template?> writeCopySessionIfAny(Request req, String sessionId, TemplateUpdateIn input) async {
  final session = await req.programChangeService.writeSession(
    ownerId: req.userId,
    actorId: req.userId,
    sessionId: sessionId,
    body: input.request,
    baseRevision: input.baseRevision,
    changeId: input.changeId,
  );
  if (session?.programId case final String programId) await tellOtherSide(req, programId);
  return session;
}

Future<bool> removeCopySessionIfAny(Request req, String sessionId) async {
  final session = await req.templatesService
      .getTemplate(userId: req.userId, templateId: sessionId)
      .then<Template?>(
        (found) => found,
        onError: (Object _) => null,
      );
  final removed = await req.programChangeService.removeSession(
    ownerId: req.userId,
    actorId: req.userId,
    sessionId: sessionId,
  );
  if (removed && session?.programId != null) await tellOtherSide(req, session!.programId!);
  return removed;
}

Future<Program?> writeCopyFieldsIfAny(Request req, String programId, ProgramUpdateIn input) async {
  final program = await req.programChangeService.writeProgramFields(
    ownerId: req.userId,
    actorId: req.userId,
    programId: programId,
    program: input.program,
    baseRevision: input.baseRevision,
    changeId: input.changeId,
  );
  if (program != null) await tellOtherSide(req, programId);
  return program;
}
