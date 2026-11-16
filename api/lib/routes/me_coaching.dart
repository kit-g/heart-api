import 'package:heart/globals/config.dart';
import 'package:heart/globals/globals.dart';
import 'package:heart/inputs/inputs.dart';
import 'package:heart/middleware/database.dart';
import 'package:heart/models/errors.dart';
import 'package:heart/models/goals.dart';
import 'package:heart/models/me_coaching.dart';
import 'package:heart/models/pagination.dart';
import 'package:heart/routes/program_changes.dart' as copies;
import 'package:heart/routes/roster.dart' show refreshRoster;
import 'package:heart_models/heart_models.dart';
import 'package:relic/relic.dart';

// A coach's reads on `/me` (heart-api#412): what the coach's assistant reads over
// MCP (docs/2026-11-09.coach-assistant.md), for a token holding `read:coaching`.
// Each is the app's own coach read with the assistant's narrower view, so the
// client's `assistant` share is checked in the statement that reads.

/// The people the user coaches, those who need a word first.
Future<Paginated<MeCoachingClient>> getMyClients(Request req, RosterQuery query) async {
  if (query.cursor == null && !query.former) await refreshRoster(req);
  final page = await req.rosterService.getRoster(
    coachId: req.userId,
    reason: query.reason,
    former: query.former,
    cursor: query.cursor,
    limit: query.limit,
    assistant: true,
  );
  return Paginated<MeCoachingClient>.from(
    Page(items: [for (final client in page.items) MeCoachingClient(client)], hasMore: page.hasMore),
    itemsKey: 'clients',
    cursorOf: (client) => OrderedCursor(
      order: !query.former && client.client.reasons.isEmpty ? 1 : 0,
      id: client.client.connectionId,
    ).toString(),
  );
}

/// What the clients who share did lately, newest first.
Future<Paginated<MeCoachFeedItem>> getMyCoachFeed(Request req, CoachFeedQuery query) async {
  if (query.cursor == null) await refreshRoster(req);
  final page = await req.rosterService.getCoachFeed(
    coachId: req.userId,
    cursor: query.cursor,
    limit: query.limit,
    assistant: true,
  );
  return Paginated<MeCoachFeedItem>.from(
    Page(items: [for (final item in page.items) MeCoachFeedItem(item)], hasMore: page.hasMore),
    itemsKey: 'items',
    cursorOf: (item) => item.item.cursor!,
  );
}

Future<Paginated<MeClientWorkout>> getClientWorkouts(Request req, ({String clientId, PageQuery page}) input) async {
  final (:clientId, :page) = input;
  if (page.cursor case final cursor? when !isUuidV7(cursor)) {
    throw const BadRequest(reason: 'cursor must be the one the previous page returned');
  }
  final workouts = await _asClient(
    req,
    clientId,
    () => _workouts(req, clientId, limit: page.limit, cursor: page.cursor),
  );
  return Paginated<MeClientWorkout>.from(
    Page(
      items: [for (final workout in workouts.items) MeClientWorkout(workout, coachId: req.userId)],
      hasMore: workouts.hasMore,
    ),
    itemsKey: 'workouts',
    cursorOf: (workout) => workout.id,
  );
}

Future<MeClientWorkout> getClientWorkout(Request req, ({String clientId, String workoutId}) input) async {
  final (:clientId, :workoutId) = input;
  if (!isUuidV7(workoutId)) throw NotFound(type: 'Workout', id: workoutId);
  final workout = await _asClient(
    req,
    clientId,
    () => req.workoutsService.getTargetWorkout(
      requesterId: req.userId,
      targetUserId: clientId,
      workoutId: workoutId,
      imageUrl: req.config.cdnAssetUrl,
      assistant: true,
    ),
  );
  return MeClientWorkout(workout, coachId: req.userId);
}

/// The copies the user sent a client.
Future<MeClientPrograms> getClientPrograms(Request req, String clientId) async {
  final programs = await _asClient(
    req,
    clientId,
    () => req.programChangeService.getCopies(coachId: req.userId, studentId: clientId, assistant: true),
  );
  // the copies read nothing for anyone who doesn't share, and saying none of
  // theirs as an empty list would answer what the other reads refuse
  if (programs.isEmpty) await _asClient(req, clientId, () => _workouts(req, clientId, limit: 1));
  return MeClientPrograms(programs);
}

Future<MeClientProgram> getClientProgram(Request req, ({String clientId, String programId}) input) async {
  final (:clientId, :programId) = input;
  if (!isUuidV7(programId)) throw NotFound(type: 'Program', id: programId, code: 'program_not_found');
  final (:read, :position) = await _asClient(
    req,
    clientId,
    () => copies.copyState(req, student: clientId, programId: programId, assistant: true),
  );
  return MeClientProgram(read.program, sessions: read.sessions, position: position, coachId: req.userId);
}

Future<MeClientProgramChanges> getClientProgramChanges(
  Request req,
  ({String clientId, String programId, String? since}) input,
) async {
  final (:clientId, :programId, :since) = input;
  if (!isUuidV7(programId)) throw NotFound(type: 'Program', id: programId, code: 'program_not_found');
  final changes = await _asClient(
    req,
    clientId,
    () => copies.copyChanges(req, student: clientId, programId: programId, since: since, assistant: true),
  );
  return MeClientProgramChanges(changes, since: since, coachId: req.userId, clientId: clientId);
}

/// A client's goals, when they share their goals with the user too.
Future<GoalsResponse> getClientGoals(Request req, ({String clientId, GoalsQuery query}) input) async {
  final (:clientId, :query) = input;
  final goals = await _asClient(
    req,
    clientId,
    () => req.goalService.getTargetUserGoals(
      requesterId: req.userId,
      targetUserId: clientId,
      archived: query.archived,
      assistant: true,
    ),
    what: 'their goals',
  );
  return GoalsResponse(goals: goals);
}

/// The user's own coaching library, newest first.
Future<Paginated<MeLibraryEntry>> getMyCoachingLibrary(Request req, PageQuery query) async {
  if (query.cursor case final cursor? when !isUuidV7(cursor)) {
    throw const BadRequest(reason: 'cursor must be the one the previous page returned');
  }
  final page = await req.coachLibraryService.getCoachPrograms(
    coachId: req.userId,
    cursor: query.cursor,
    limit: query.limit,
  );
  return Paginated<MeLibraryEntry>.from(
    Page(items: [for (final program in page.items) MeLibraryEntry(program)], hasMore: page.hasMore),
    itemsKey: 'programs',
    cursorOf: (program) => program.id,
  );
}

Future<MeLibraryProgram> getMyCoachingLibraryProgram(Request req, String programId) async {
  final missing = NotFound(type: 'Library program', id: programId, code: 'program_not_found');
  if (!isUuidV7(programId)) throw missing;
  try {
    return MeLibraryProgram(await req.coachLibraryService.getCoachProgram(coachId: req.userId, id: programId));
  } on NotFound {
    throw missing;
  }
}

/// [read], refused as `not_shared` for anyone who isn't a client sharing [what]
/// with the user's apps and assistants, the user themselves included.
Future<T> _asClient<T>(
  Request req,
  String clientId,
  Future<T> Function() read, {
  String what = 'their training',
}) async {
  final refused = Forbidden(
    code: 'not_shared',
    reason: "$clientId isn't a client who shares $what with your apps and assistants",
  );
  if (clientId == req.userId) throw refused;
  try {
    return await read();
  } on Forbidden {
    throw refused;
  }
}

/// A page of [clientId]'s workouts, as the user's assistant reads them.
Future<Page<Workout>> _workouts(Request req, String clientId, {required int limit, String? cursor}) {
  return req.workoutsService.getWorkouts(
    userId: req.userId,
    targetUserId: clientId,
    limit: limit,
    cursor: cursor,
    imageUrl: req.config.cdnAssetUrl,
    assistant: true,
  );
}
