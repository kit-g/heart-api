library;

import 'dart:convert';

import 'package:heart/models/errors.dart';
import 'package:heart/models/exercises.dart';
import 'package:heart/models/images.dart';
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
part 'images.dart';
part 'profiles.dart';
part 'queries.dart';
part 'templates.dart';
part 'workouts.dart';

abstract class _DatabaseBase {
  Pool get _pool;
}

class Database extends _DatabaseBase
    with
        _Charts,
        _Comments,
        _Connections,
        _Devices,
        _ExercisePreferences,
        _Exercises,
        _Images,
        _Profiles,
        _Workouts,
        _Templates
    implements
        ChartPreferenceService,
        ExercisePreferenceService,
        CommentService,
        ConnectionsService,
        DeviceService,
        ExerciseService,
        ApiImageDbService,
        ApiProfileService,
        ApiWorkoutService,
        ApiTemplateService {
  @override
  final Pool _pool;

  Database({required this._pool});
}
