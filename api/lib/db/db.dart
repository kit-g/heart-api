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
