part of 'db.dart';

mixin _Push on _DatabaseBase implements PushService {
  @override
  Future<List<PushPreference>> getPushPreferences({required String userId}) async {
    final rows = await _pool.execute(_listPushPreferences.toSql(), parameters: {'userId': userId});
    return [
      for (final row in rows.map((row) => row.toColumnMap()))
        (
          topic: row['topic'] as String,
          connectionId: row['connection_id']?.toString(),
          delivery: row['delivery'] as String,
        ),
    ];
  }

  @override
  Future<void> setPushPreference({
    required String userId,
    required String topic,
    required String delivery,
    String? connectionId,
  }) async {
    final rows = await _pool.execute(
      switch (connectionId) {
        null => _setPushPreferenceForTopic.toSql(),
        _ => _setPushPreferenceForPerson.toSql(),
      },
      parameters: {'userId': userId, 'topic': topic, 'delivery': delivery, 'connectionId': ?connectionId},
    );
    if (rows.isEmpty) throw NotFound(type: 'Connection', id: connectionId ?? topic);
  }

  @override
  Future<void> clearPushPreference({required String userId, required String topic, String? connectionId}) async {
    await _pool.execute(
      _clearPushPreference.toSql(),
      parameters: {'userId': userId, 'topic': topic, 'connectionId': connectionId},
    );
  }

  @override
  Future<PushAudience> getPushAudience({
    required String userId,
    required String topic,
    String? connectionId,
    String? actorId,
  }) async {
    final rows = await _pool.execute(
      _pushAudience.toSql(),
      parameters: {'userId': userId, 'topic': topic, 'connectionId': connectionId, 'actorId': actorId},
    );
    final row = rows.first.toColumnMap();
    return (
      blocked: row['blocked'] as bool,
      forPerson: row['for_person'] as String?,
      forTopic: row['for_topic'] as String?,
      devices: [
        for (final device in row['devices'] as List)
          (token: (device as Map)['token'] as String, locale: device['locale'] as String),
      ],
    );
  }

  @override
  Future<void> queueDigest({required String userId, required String topic}) async {
    await _pool.execute(_queueDigest.toSql(), parameters: {'userId': userId, 'topic': topic});
  }

  @override
  Future<List<({String userId, String topic})>> claimDueDigests({required int localHour}) async {
    final rows = await _pool.execute(_claimDueDigests.toSql(), parameters: {'localHour': localHour});
    return [
      for (final row in rows.map((row) => row.toColumnMap()))
        (userId: row['user_id'] as String, topic: row['topic'] as String),
    ];
  }
}
