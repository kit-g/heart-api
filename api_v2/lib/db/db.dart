library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:aws_client/dynamo_document.dart';
import 'package:heart/models/av.dart';
import 'package:heart/models/connections.dart';
import 'package:heart/models/errors.dart';
import 'package:heart_models/heart_models.dart' hide WorkoutService, TemplateService;

import '../models/profile.dart';
import '../models/templates.dart';
import '../models/workouts.dart';

part 'charts.dart';
part 'connections.dart';
part 'templates.dart';
part 'workouts.dart';

const _userPk = 'USER#';
const _connectionPk = _userPk;
const _connectionSk = 'CONN#';
const _workoutSk = 'WORKOUT#';
const _templateSk = 'TEMPLATE#';
const _templateShareSk = 'TEMPLATE_SHARE#';

abstract class _DatabaseBase {
  DocumentClient get _client;

  const _DatabaseBase();

  String connectionPk(String userId) => '$_connectionPk$userId';

  String connectionSk(ConnectionRole role, ConnectionDomain domain, String targetId) {
    return '$_connectionSk${role.value.toUpperCase()}#${domain.value.toUpperCase()}#$targetId';
  }

  String templatePk(String userId) => '$_userPk$userId';

  String templateSk(String templateId) => '$_templateSk$templateId';
}

class Database extends _DatabaseBase
    with _Charts, _Connections, _Workouts, _Templates
    implements ChartPreferenceService, ConnectionsService, ApiWorkoutService, ApiTemplateService {
  @override
  final DocumentClient _client;
  @override
  final String table;

  const Database({
    required DocumentClient client,
    required this.table,
  }) : _client = client;
}

AttributeValue toDynamoType(Object? v) {
  return switch (v) {
    String s => AttributeValue(s: s),
    num n => AttributeValue(n: n.toString()),
    bool b => AttributeValue(boolValue: b),
    null => AttributeValue(nullValue: true),
    Uint8List bytes => AttributeValue(b: bytes),
    Map m => AttributeValue(m: m.map((k, v) => MapEntry(k, toDynamoType(v)))),
    List l => AttributeValue(l: l.map((v) => toDynamoType(v)).toList()),
    _ => throw ArgumentError('Unsupported DynamoDB type: ${v.runtimeType} - $v'),
  };
}

extension on Map<String, dynamic> {
  Map<String, AttributeValue> toAttributeValue() {
    return map((k, v) => MapEntry(k, toDynamoType(v)));
  }
}

extension on DynamoItem {
  Map<String, AttributeValue> toAttributeValue() {
    return toDynamoItem().toAttributeValue();
  }
}
