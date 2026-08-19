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
