part of 'db.dart';

/// Single-use keys a device can hold.
const _maxOneTimeKeys = 50;

/// How many times an hour one person can take another's single-use keys.
const _maxKeyClaims = 60;

/// Unconfirmed items from one device to another. About where a pair needs a new
/// session anyway, so anything past it is a sign something is wrong.
const _maxQueuedPerPair = 2000;

mixin _Keys on _DatabaseBase implements KeyService {
  @override
  Future<CryptoDevice> publishDevice({
    required String userId,
    required String id,
    required String identityKey,
    required String signingKey,
    required String fallbackKey,
    String? signature,
    String? vouchedBy,
  }) async {
    final rows = await _pool.execute(
      _publishDevice.toSql(),
      parameters: {
        'userId': userId,
        'id': id,
        'identityKey': identityKey,
        'signingKey': signingKey,
        'fallbackKey': fallbackKey,
        'signature': signature,
        'vouchedBy': vouchedBy,
      },
    );
    if (rows.isEmpty) throw const Forbidden(code: 'id_taken', reason: 'this id belongs to another account');
    return CryptoDevice.fromRow(rows.first.toColumnMap());
  }

  @override
  Future<List<CryptoDevice>> getDevices({required String readerId, required String ownerId}) async {
    final rows = await _pool.execute(_listDevices.toSql(), parameters: {'readerId': readerId, 'ownerId': ownerId});
    final maps = rows.map((row) => row.toColumnMap()).toList();
    if (maps.first['allowed'] != true) {
      throw const Forbidden(reason: 'You do not have permission to see these devices.');
    }
    return [
      for (final map in maps)
        if (map['id'] != null) CryptoDevice.fromRow(map),
    ];
  }

  @override
  Future<void> removeDevice({required String userId, required String deviceId}) async {
    await _pool.execute(_removeDevice.toSql(), parameters: {'userId': userId, 'deviceId': deviceId});
  }

  @override
  Future<void> replaceFallbackKey({required String userId, required String deviceId, required String key}) async {
    final rows = await _pool.execute(
      _replaceFallbackKey.toSql(),
      parameters: {'userId': userId, 'deviceId': deviceId, 'key': key},
    );
    if (rows.isEmpty) throw NotFound(type: 'Device', id: deviceId);
  }

  @override
  Future<int> addOneTimeKeys({
    required String userId,
    required String deviceId,
    required Map<String, String> keys,
  }) async {
    final rows = await _pool.execute(
      _addOneTimeKeys.toSql(),
      parameters: {
        'userId': userId,
        'deviceId': deviceId,
        'keys': jsonEncode([
          for (final MapEntry(:key, :value) in keys.entries) {'id': key, 'key': value},
        ]),
      },
    );
    final row = rows.first.toColumnMap();
    return switch (row) {
      {'owned': false} => throw NotFound(type: 'Device', id: deviceId),
      {'fits': false} => throw const BadRequest(
        code: 'key_limit',
        reason: 'a device holds at most $_maxOneTimeKeys keys',
      ),
      _ => (row['count'] as num).toInt(),
    };
  }

  @override
  Future<int> countOneTimeKeys({required String userId, required String deviceId}) async {
    final rows = await _pool.execute(_countOneTimeKeys.toSql(), parameters: {'userId': userId, 'deviceId': deviceId});
    final row = rows.first.toColumnMap();
    if (row['owned'] != true) throw NotFound(type: 'Device', id: deviceId);
    return (row['count'] as num).toInt();
  }

  @override
  Future<List<CryptoDevice>> claimKeys({required String claimerId, required String ownerId}) async {
    final rows = await _pool.execute(_claimKeys.toSql(), parameters: {'claimerId': claimerId, 'ownerId': ownerId});
    final maps = rows.map((row) => row.toColumnMap()).toList();
    final first = maps.first;
    if (first['allowed'] != true) {
      throw const Forbidden(reason: 'You do not have permission to take these keys.');
    }
    if ((first['claims'] as num).toInt() > _maxKeyClaims) {
      throw const TooManyRequests(reason: 'too many key requests for this person', retryAfter: 3600);
    }
    return [
      for (final map in maps)
        if (map['id'] != null) CryptoDevice.fromRow(map),
    ];
  }

  @override
  Future<bool> enqueue({
    required String userId,
    required String id,
    required String recipientDeviceId,
    required String senderDeviceId,
    required String kind,
    required String content,
  }) async {
    final rows = await _pool.execute(
      _enqueue.toSql(),
      parameters: {
        'userId': userId,
        'id': id,
        'recipientDeviceId': recipientDeviceId,
        'senderDeviceId': senderDeviceId,
        'kind': kind,
        'content': content,
      },
    );
    final row = rows.first.toColumnMap();
    return switch (row) {
      {'seen': true} => false,
      {'sender_owned': false} => throw NotFound(type: 'Device', id: senderDeviceId),
      {'allowed': false} => throw const Forbidden(reason: 'You do not have permission to reach this device.'),
      {'is_full': true} => throw const BadRequest(code: 'queue_full', reason: 'this device has too much waiting'),
      _ => true,
    };
  }

  @override
  Future<List<QueuedItem>> getQueue({required String userId, required String deviceId, int limit = 100}) async {
    final rows = await _pool.execute(
      _listQueue.toSql(),
      parameters: {'userId': userId, 'deviceId': deviceId, 'limit': limit},
    );
    return rows.map((row) => QueuedItem.fromRow(row.toColumnMap())).toList();
  }

  @override
  Future<void> confirm({required String userId, required String deviceId, required List<String> ids}) async {
    await _pool.execute(_confirmQueued.toSql(), parameters: {'userId': userId, 'deviceId': deviceId, 'ids': ids});
  }

  @override
  Future<List<String>> getKeyPeers({required String userId}) async {
    final rows = await _pool.execute(_listKeyPeers.toSql(), parameters: {'userId': userId});
    return [for (final row in rows) row[0] as String];
  }
}
