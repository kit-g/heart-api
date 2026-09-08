library;

import 'dart:convert';

import 'package:heart/models/creates.dart';
import 'package:heart/models/errors.dart';
import 'package:heart/models/exercise_preferences.dart';
import 'package:heart/models/exercises.dart';
import 'package:heart/models/images.dart';
import 'package:heart/models/imports.dart';
import 'package:heart/models/profile.dart';
import 'package:heart/models/workouts.dart';
import 'package:heart_models/heart_models.dart' hide WorkoutService, TemplateService, ExerciseService;
import 'package:postgres/postgres.dart' hide Connection;

part 'charts.dart';
part 'comments.dart';
part 'connections.dart';
part 'devices.dart';
part 'exercise_preferences.dart';
part 'exercises.dart';
part 'goals.dart';
part 'images.dart';
part 'profiles.dart';
part 'queries.dart';
part 'template_folders.dart';
part 'templates.dart';
part 'workouts.dart';

abstract class _DatabaseBase {
  Pool get _pool;

  /// Translates the DB-enforced volume ceilings into 400s. Every such trigger
  /// (imported workouts per user, sets/exercises per workout or template,
  /// custom exercises per user) raises `check_violation` with a
  /// `<what> cap (<n>) exceeded for <owner>` message; hitting one is a client
  /// exceeding its allowance, not a server fault. Anything else rethrows —
  /// including genuine table CHECK violations, which are bugs.
  Never _rethrowCapped(ServerException e) {
    if (e.code == '23514' && e.message.contains(' cap (')) {
      throw BadRequest(reason: 'limit reached: ${e.message.split(' exceeded').first}');
    }
    throw e;
  }

  /// Client-minted ids that have no owner of their own (a workout's exercises
  /// and sets round-trip into plain INSERTs) so an id that already exists — a
  /// duplicate within the payload, a stale copy, or a hostile probe — surfaces
  /// as a unique violation. That's the client's mistake: reject it as a 400
  /// instead of letting the 23505 bubble up as a 500.
  static const _clientIdConstraints = {'workout_exercises_pkey', 'exercise_sets_pkey'};

  Never _rethrowClientIdCollision(ServerException e) {
    if (e.code == '23505' && _clientIdConstraints.contains(e.constraintName)) {
      throw const BadRequest(reason: 'an exercise or set id in the payload already exists');
    }
    _rethrowForeignId(e);
  }

  /// The five upsync-replay creates (heart-api#66) pre-check every id
  /// against `user_id = @userId` before inserting, so if the insert itself
  /// still trips one of these primary keys, the only way that happens is the
  /// id belongs to someone else (or, for exercises, a global row) — a hostile
  /// or buggy replay, never a legitimate retry. `403 id_taken`, not the 400 a
  /// same-payload collision gets: the row is real, just not this caller's.
  static const _foreignIdConstraints = {
    'exercises_pkey',
    'workouts_pkey',
    'templates_pkey',
    'template_folders_pkey',
    'goals_pkey',
  };

  Forbidden get _idTaken => const Forbidden(code: 'id_taken', reason: 'this id belongs to another account');

  Never _rethrowForeignId(ServerException e) {
    if (e.code == '23505' && _foreignIdConstraints.contains(e.constraintName)) {
      throw _idTaken;
    }
    _rethrowCapped(e);
  }

  /// The natural-key half of the upsync replay's idempotent creates
  /// (heart-api#66) — a name the caller already uses resolving to that
  /// row instead of erroring — is enforced by real unique indexes distinct
  /// from the id-scoped ones in [_foreignIdConstraints].
  static const _raceableNameConstraints = {'exercises_user_name_idx', 'template_folders_user_name_idx'};

  /// Every idempotent-create statement (`_createExercise`, `_saveWorkout`,
  /// `_saveTemplate`, `_createTemplateFolder`, `_createGoal`) pre-checks its id
  /// (and, for exercises/folders, its name) against rows the caller already
  /// owns *before* inserting — but that pre-check and the insert are two
  /// separate statements-in-a-CTE, not one atomic step, so two genuinely
  /// concurrent replays of the *same* create (the exact flaky-network/backgrounded-app
  /// scenario the replay exists for) can both pass the pre-check before either
  /// commits. The loser then trips a real unique violation that looks
  /// identical to a hostile probe of someone else's id or name — [attempt]
  /// run once more re-executes the pre-check, which now sees whichever row
  /// committed first: if it was this caller's own (the race, not a conflict),
  /// the retry resolves normally as `created: false`. If it wasn't — a
  /// genuinely foreign id — the retry fails the same way and the caller's own
  /// exception mapping (`_rethrowForeignId` / `_rethrowCapped`) classifies it.
  Future<T> _retryOnCreateRace<T>(Future<T> Function() attempt) async {
    try {
      return await attempt();
    } on ServerException catch (e) {
      final raceable =
          _foreignIdConstraints.contains(e.constraintName) || _raceableNameConstraints.contains(e.constraintName);
      if (e.code != '23505' || !raceable) rethrow;
      return await attempt();
    }
  }
}

/// Constraint violations that name a specific client-supplied reference, mapped
/// to the `code` the app branches on. Every one of these is a row the caller
/// asked for by id; the response is the same whether that row is absent or
/// merely someone else's, so it never confirms another account's data exists.
const _missingReferenceCodes = <String, String>{
  'exercise_preferences_exercise_id_fkey': 'unknown_exercise',
  'goals_exercise_id_fkey': 'unknown_exercise',
  'workout_exercises_exercise_id_fkey': 'unknown_exercise',
  'template_exercises_exercise_id_fkey': 'unknown_exercise',
  'templates_folder_fk': 'unknown_folder',
  'comments_workout_id_fkey': 'unknown_comment_target',
  'comments_workout_exercise_id_fkey': 'unknown_comment_target',
  'comments_exercise_set_id_fkey': 'unknown_comment_target',
  'comments_workout_image_id_fkey': 'unknown_comment_target',
};

/// The last line of defence for a constraint violation no statement mapped:
/// `apiHandler` consults this before falling through to a 500.
///
/// The `_rethrow*` mappings above are *precise* — a specific statement opts
/// into one and gets a specific code, and those still win, because they run at
/// the call site long before this does. This exists for everything that opted
/// into nothing: 62 statements reach the pool and 8 wrap themselves, so a
/// foreign-key violation from any of the other 54 escaped as
/// `500 server_error` (heart-api#74 — a replayed unit preference for an
/// exercise id the account did not own killed a 358-row backup at row 26,
/// because a 500 is indistinguishable from an outage and the app stopped).
///
/// A `23503` is always the caller naming a row that is not there: the statement
/// supplies every other value itself, so the only reference that can go
/// unsatisfied is one that arrived in the request. Known ones carry a specific
/// code; anything else still lands on a 400 rather than a 500, so a foreign key
/// added later cannot silently reopen this.
ApiException? apiExceptionForDbError(Object error) {
  if (error is! ServerException) return null;
  final constraint = error.constraintName;
  return switch (error.code) {
    '23503' => switch (_missingReferenceCodes[constraint]) {
      final String code => NotFound(type: 'Reference', id: constraint ?? 'unknown', code: code),
      // An unmapped foreign key: still the client's reference, but we can't say
      // which one, so it stays a 400 rather than claiming a specific 404.
      null => const BadRequest(code: 'invalid_reference', reason: 'a referenced record does not exist'),
    },
    // Reached only when no call site claimed it — the specific duplicate codes
    // (`id_taken`, the payload-id collision) are thrown at their statements.
    '23505' => const BadRequest(code: 'duplicate', reason: 'a record with these values already exists'),
    _ => null,
  };
}

class Database extends _DatabaseBase
    with
        _Charts,
        _Comments,
        _Connections,
        _Devices,
        _ExercisePreferences,
        _Exercises,
        _Goals,
        _Images,
        _Profiles,
        _Workouts,
        _Templates,
        _TemplateFolders
    implements
        ChartPreferenceService,
        ApiExercisePreferenceService,
        CommentService,
        ConnectionsService,
        DeviceService,
        ExerciseService,
        IdempotentGoalService,
        ApiImageDbService,
        ApiProfileService,
        ApiWorkoutService,
        IdempotentTemplateService,
        IdempotentTemplateFolderService {
  @override
  final Pool _pool;

  new({required this._pool});
}
