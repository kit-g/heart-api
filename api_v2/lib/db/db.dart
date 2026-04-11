library;

import 'dart:convert';

import 'package:aws_client/dynamo_document.dart';
import 'package:heart/models/connections.dart';
import 'package:heart_models/heart_models.dart' hide WorkoutService;

import '../models/workouts.dart';

part 'charts.dart';
part 'connections.dart';
part 'workouts.dart';

abstract class _DatabaseBase {
  DocumentClient get _client;

  const _DatabaseBase();
}

class Database extends _DatabaseBase
    with _Charts, _Connections, _Workouts
    implements ChartPreferenceService, ConnectionsService, ApiWorkoutService {
  @override
  final DocumentClient _client;
  @override
  final String table;

  const Database({
    required DocumentClient client,
    required this.table,
  }) : _client = client;
}

const _userPk = 'USER#';
const _connectionPk = _userPk;
const _connectionSk = 'CONN#';
const _workoutSk = 'WORKOUT#';