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
