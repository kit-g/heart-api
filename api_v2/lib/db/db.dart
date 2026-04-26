library;

import 'package:heart/models/connections.dart';
import 'package:heart/models/errors.dart';
import 'package:heart/models/profile.dart';
import 'package:heart/models/templates.dart';
import 'package:heart/models/workouts.dart';
import 'package:heart_models/heart_models.dart' hide WorkoutService, TemplateService;
import 'package:postgres/postgres.dart' hide Connection;

part 'charts.dart';
part 'connections.dart';
part 'profiles.dart';
part 'queries.dart';
part 'templates.dart';
part 'workouts.dart';

abstract class _DatabaseBase {
  Pool get _pool;
}

class Database extends _DatabaseBase
    with _Charts, _Connections, _Profiles, _Workouts, _Templates
    implements ChartPreferenceService, ConnectionsService, ApiProfileService, ApiWorkoutService, ApiTemplateService {
  @override
  final Pool _pool;

  Database({required Pool pool}) : _pool = pool;
}
