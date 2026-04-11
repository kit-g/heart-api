part of 'db.dart';

mixin _Workouts on _DatabaseBase implements ApiWorkoutService {
  String get table;

  static String pk(String userId) => '$_userPk$userId';

  static String sk(String workoutId) => '$_workoutSk$workoutId';

  @override
  Future<WorkoutListResponse> getWorkouts({
    required String userId,
    required String targetUserId,
    required String Function(String) imageUrl,
    String? cursor,
    int? pageSize = 30,
  }) async {
    final response = await _client.query(
      tableName: table,
      keyConditionExpression: '#PK = :PK AND begins_with(#SK, :PREFIX)',
      expressionAttributeNames: {
        '#PK': 'PK',
        '#SK': 'SK',
      },
      expressionAttributeValues: {
        ':PK': AttributeValue(s: pk(targetUserId)),
        ':PREFIX': AttributeValue(s: _workoutSk),
      },
      scanIndexForward: false,
      limit: pageSize,
      exclusiveStartKey: switch (cursor?.fromBase64()) {
        String s when s.isNotEmpty => {
          'PK': AttributeValue(s: pk(userId)),
          'SK': AttributeValue(s: sk(s)),
        },
        _ => null,
      },
    );

    return WorkoutListResponse(
      workouts: response.items.map((item) => WorkoutItem.fromRow(item, imageUrl: imageUrl)).toList(),
      cursor: (response.lastEvaluatedKey['SK'] as String?)?.split('#').lastOrNull?.toBase64(),
    );
  }
}

extension on String {
  String? toBase64() {
    try {
      return base64Encode(utf8.encode(this));
    } catch (_) {
      return null;
    }
  }

  String? fromBase64() {
    try {
      return utf8.decode(base64Decode(this));
    } catch (_) {
      return null;
    }
  }
}
