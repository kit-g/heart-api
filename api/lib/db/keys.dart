part of 'db.dart';

/// Devices with keys an account can have in use: a beta guard, not a promise.
const _maxDevices = 10;

/// Single-use keys a device can hold.
const _maxOneTimeKeys = 50;

/// How many times an hour one person can take another's single-use keys.
const _maxKeyClaims = 60;

/// Unconfirmed items from one device to another. About where a pair needs a new
/// session anyway, so anything past it is a sign something is wrong.
const _maxQueuedPerPair = 2000;

const _badSignature = BadRequest(code: 'bad_signature', reason: 'the signature does not check out');

/// What one device signs to vouch for another of the same owner's, spelled as the
/// app spells it.
String _vouchMessage({
  required String userId,
  required String deviceId,
  required String identityKey,
  required String signingKey,
}) {
  return ['heart-of.me/vouch/v1', userId, deviceId, identityKey, signingKey].join('\n');
}

/// What a device signs to remove one of the account's devices. A removed device
/// can't come back, so the same signature sent again removes nothing.
String _removalMessage({required String userId, required String deviceId}) {
  return ['heart-of.me/remove-device/v1', userId, deviceId].join('\n');
}

/// A device's public keys, as it signs with them.
typedef _Signer = ({String identityKey, String signingKey});

extension on _Signer {
  /// Whether [signature], base64 with or without padding, is this device's
  /// Ed25519 signature over [message]. A key or a signature that isn't one signs
  /// nothing.
  Future<bool> signed(String message, String signature) async {
    try {
      final key = base64.decode(base64.normalize(signingKey));
      final bytes = base64.decode(base64.normalize(signature));
      if (key.length != 32 || bytes.length != 64) return false;
      return await Ed25519().verify(
        utf8.encode(message),
        signature: Signature(bytes, publicKey: SimplePublicKey(key, type: .ed25519)),
      );
    } on FormatException {
      return false;
    }
  }
}

mixin _Keys on _DatabaseBase implements KeyService {
  @override
  Future<({CryptoDevice device, bool added})> publishDevice({
    required String userId,
    required String id,
    required String identityKey,
    required String signingKey,
    required String fallbackKey,
    String? signature,
    String? vouchedBy,
  }) async {
    Future<Map<String, dynamic>?> publish(TxSession tx) async {
      final rows = await tx.execute(
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
      return rows.firstOrNull?.toColumnMap();
    }

    // A publish racing another of the same id waits for it, then reads from a
    // snapshot taken before it committed and finds nothing. Asking again sees it.
    final row = await _pool.runTx((tx) async {
      await tx.execute(_lockDevices.toSql(), parameters: {'userId': userId});
      // a vouch that doesn't check out is no vouch, as one by somebody else's
      // device is none
      if ((vouchedBy, signature) case (final String by, final String said)) {
        final voucher = (await _signersOf(tx, userId: userId, ids: [by]))[by];
        final message = _vouchMessage(
          userId: userId,
          deviceId: id,
          identityKey: identityKey,
          signingKey: signingKey,
        );
        if (voucher != null && !await voucher.signed(message, said)) (vouchedBy, signature) = (null, null);
      }
      return await publish(tx) ?? await publish(tx);
    });
    return switch (row) {
      null => throw _idTaken,
      {'is_full': true} => throw const Conflict(
        code: 'device_limit',
        reason: 'an account has at most $_maxDevices devices with keys; remove one first',
      ),
      {'removed': true} => throw const Forbidden(code: 'device_removed', reason: 'this device was removed'),
      _ => (device: CryptoDevice.fromRow(row), added: row['added'] == true),
    };
  }

  @override
  Future<({CryptoDevice device, bool changed})> vouchForDevice({
    required String userId,
    required String deviceId,
    required String vouchedBy,
    required String signature,
  }) async {
    Future<Map<String, dynamic>> vouch(TxSession tx) async {
      final rows = await tx.execute(
        _vouchForDevice.toSql(),
        parameters: {'userId': userId, 'deviceId': deviceId, 'vouchedBy': vouchedBy, 'signature': signature},
      );
      return rows.first.toColumnMap();
    }

    final row = await _pool.runTx((tx) async {
      await tx.execute(_lockDevices.toSql(), parameters: {'userId': userId});
      final signers = await _signersOf(tx, userId: userId, ids: [deviceId, vouchedBy]);
      if ((signers[deviceId], signers[vouchedBy]) case (final device?, final voucher?) when deviceId != vouchedBy) {
        final message = _vouchMessage(
          userId: userId,
          deviceId: deviceId,
          identityKey: device.identityKey,
          signingKey: device.signingKey,
        );
        if (!await voucher.signed(message, signature)) throw _badSignature;
      }
      // A vouch racing another sees the device unvouched in its snapshot, and the
      // other's vouch only when it asks again.
      final row = await vouch(tx);
      return switch (row) {
        {'owned': true, 'changed': false, 'voucher_owned': true, 'vouched_by': null} => await vouch(tx),
        _ => row,
      };
    });
    return switch (row) {
      {'owned': false} => throw NotFound(type: 'Device', id: deviceId),
      {'changed': true} => (device: CryptoDevice.fromRow(row), changed: true),
      {'vouched_by': final by, 'signature': final said} when '$by' == vouchedBy && said == signature => (
        device: CryptoDevice.fromRow(row),
        changed: false,
      ),
      {'voucher_owned': false} => throw const BadRequest(reason: 'vouchedBy must be another device of yours'),
      _ => throw const Conflict(code: 'already_vouched', reason: 'this device is already vouched for'),
    };
  }

  @override
  Future<List<CryptoDevice>> getDevices({required String readerId, required String ownerId}) async {
    final rows = await _pool.execute(_listDevices.toSql(), parameters: {'readerId': readerId, 'ownerId': ownerId});
    final maps = rows.map((row) => row.toColumnMap()).toList();
    if (maps.first['forbidden'] == true) {
      throw const Forbidden(reason: 'You do not have permission to see these devices.');
    }
    return [
      for (final map in maps)
        if (map['id'] != null) CryptoDevice.fromRow(map),
    ];
  }

  @override
  Future<void> removeDevice({
    required String userId,
    required String deviceId,
    String? removedBy,
    String? signature,
  }) async {
    final row = await _pool.runTx((tx) async {
      await tx.execute(_lockDevices.toSql(), parameters: {'userId': userId});
      // a device that isn't the caller's in use asks as nobody would
      final by = switch ((removedBy, signature)) {
        (final String by, final String said) => switch ((await _signersOf(tx, userId: userId, ids: [by]))[by]) {
          final signer? when await signer.signed(_removalMessage(userId: userId, deviceId: deviceId), said) => by,
          null => null,
          _ => throw _badSignature,
        },
        _ => null,
      };
      final rows = await tx.execute(
        _removeDevice.toSql(),
        parameters: {'userId': userId, 'deviceId': deviceId, 'removedBy': by},
      );
      return rows.first.toColumnMap();
    });
    switch (row) {
      case {'found': false}:
        throw NotFound(type: 'Device', id: deviceId);
      case {'removed': false}:
        throw const Forbidden(
          code: 'vouch_required',
          reason: 'a device that was vouched for, or vouched for another, is removed from one the account trusts',
        );
    }
  }

  Future<Map<String, _Signer>> _signersOf(TxSession tx, {required String userId, required List<String> ids}) async {
    final rows = await tx.execute(_signers.toSql(), parameters: {'userId': userId, 'ids': ids});
    return {
      for (final row in rows) row[0].toString(): (identityKey: row[1] as String, signingKey: row[2] as String),
    };
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
    final row = await _pool.runTx((tx) async {
      await tx.execute(_lockDevice.toSql(), parameters: {'userId': userId, 'deviceId': deviceId});
      final rows = await tx.execute(
        _addOneTimeKeys.toSql(),
        parameters: {
          'userId': userId,
          'deviceId': deviceId,
          'keys': jsonEncode([
            for (final MapEntry(:key, :value) in keys.entries) {'id': key, 'key': value},
          ]),
        },
      );
      return rows.first.toColumnMap();
    });
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
  Future<List<CryptoDevice>> claimKeys({
    required String claimerId,
    required String ownerId,
    List<String>? deviceIds,
  }) async {
    final rows = await _pool.execute(
      _claimKeys.toSql(),
      parameters: {'claimerId': claimerId, 'ownerId': ownerId, 'deviceIds': deviceIds},
    );
    final maps = rows.map((row) => row.toColumnMap()).toList();
    final first = maps.first;
    if (first['forbidden'] == true) {
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
  Future<({bool delivered, String? notify})> enqueue({
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
      {'sender_owned': false} => throw NotFound(type: 'Device', id: senderDeviceId),
      {'forbidden': true} => throw const Forbidden(reason: 'You do not have permission to reach this device.'),
      {'taken': true} => throw _idTaken,
      {'seen': true} => (delivered: false, notify: null),
      {'is_full': true} => throw const BadRequest(code: 'queue_full', reason: 'this device has too much waiting'),
      _ => (delivered: row['inserted'] == true, notify: row['notify'] as String?),
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
