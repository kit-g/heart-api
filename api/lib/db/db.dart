library;

import 'dart:convert';

import 'package:heart/models/errors.dart';
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

  /// Client-sent workout-exercise/set ids round-trip into plain INSERTs, so an
  /// id that already exists — a duplicate within the payload, a stale copy, or
  /// a hostile probe — surfaces as a unique violation. That's the client's
  /// mistake: reject it as a 400 instead of letting the 23505 bubble up as a
  /// 500 (the same reasoning that puts ON CONFLICT DO NOTHING on the
  /// create-exercise path).
  static const _clientIdConstraints = {'workout_exercises_pkey', 'exercise_sets_pkey'};

  Never _rethrowClientIdCollision(ServerException e) {
    if (e.code == '23505' && _clientIdConstraints.contains(e.constraintName)) {
      throw const BadRequest(reason: 'an exercise or set id in the payload already exists');
    }
    _rethrowCapped(e);
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
        ExercisePreferenceService,
        CommentService,
        ConnectionsService,
        DeviceService,
        ExerciseService,
        GoalService,
        ApiImageDbService,
        ApiProfileService,
        ApiWorkoutService,
        ApiTemplateService,
        ApiTemplateFolderService {
  @override
  final Pool _pool;

  new({required this._pool});
}
