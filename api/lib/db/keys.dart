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

const _removerRemoved = Forbidden(code: 'device_removed', reason: 'the device asking was removed');

/// A device waiting for a place: known, but nothing goes to or from it yet.
const _waiting = Conflict(
  code: 'device_waiting',
  reason: 'the account is full: this device waits for a place, and may remove one of its devices',
);

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
String _removalMessage({required String userId, required String deviceId, required int signedAt}) {
  return ['heart-of.me/remove-device/v1', userId, deviceId, '$signedAt'].join('\n');
}

/// How far a removal's signing time may be from the server's clock, either way: long
/// enough for a phone's clock, short enough that a signature left in a log is spent.
const _removalWindow = Duration(minutes: 10);

/// How long a device is in use before it may remove one added before it: long enough
/// for the owner's older devices to see a device they didn't add and remove it first.
const _removalWaitHours = 24;

/// How long a removed device stays on its owner's list, saying who removed it.
const _removedListedDays = 30;

/// How many removed devices the owner's list shows at most, the latest first.
const _maxRemovedListed = 20;

/// How many devices seen within a month an account can have waiting for a place: as
/// many as there are places, and a script can't add rows without end. One gone quiet
/// stops counting, as a placed one does.
const _maxWaitingDevices = _maxDevices;

/// How long a device goes without publishing itself or reading its queue before it
/// stops holding one of the account's places, so an account whose every device was
/// wiped or lost can add one, which then removes them.
const _unseenDays = 30;

/// A device's public keys, as it signs with them, whether it was removed, and whether
/// it waits for a place.
typedef _Signer = ({String identityKey, String signingKey, bool removed, bool waiting});

extension on _Signer {
  /// Whether [signature], base64 with or without padding, is this device's
  /// Ed25519 signature over [message]. A key or a signature that isn't one signs
  /// nothing.
  Future<bool> signed(String message, String signature) async {
    final (key, bytes) = (signingKey.bytes, signature.bytes);
    if (key?.length != 32 || bytes?.length != 64) return false;
    return Ed25519().verify(
      utf8.encode(message),
      signature: Signature(bytes!, publicKey: SimplePublicKey(key!, type: .ed25519)),
    );
  }
}

extension on String {
  /// The bytes of base64, padded or not, standard or URL-safe; null if it isn't.
  List<int>? get bytes {
    try {
      return base64.decode(base64.normalize(this));
    } on FormatException {
      return null;
    }
  }

  /// Whether two spellings of base64 hold the same bytes.
  bool sameBytes(String other) {
    final (mine, theirs) = (bytes, other.bytes);
    return mine != null && theirs != null && base64.encode(mine) == base64.encode(theirs);
  }
}

mixin _Keys on _DatabaseBase implements KeyService {
  // Device ids are UUIDs, which Postgres reads in either case and answers in lower
  // case: every id is lowered first, so one sent in upper case finds its signer.

  @override
  Future<({CryptoDevice device, bool added, bool waiting})> publishDevice({
    required String userId,
    required String id,
    required String identityKey,
    required String signingKey,
    required String fallbackKey,
    String? signature,
    String? vouchedBy,
  }) async {
    id = id.toLowerCase();
    // a vouch that doesn't check out, or by a device that isn't the caller's in
    // use, or half of one, is no vouch
    (vouchedBy, signature) = switch ((vouchedBy?.toLowerCase(), signature)) {
      (final String by, final String said) => switch ((await _signersOf(userId: userId, ids: [by]))[by]) {
        final voucher?
            when !voucher.removed &&
                !voucher.waiting &&
                await voucher.signed(
                  _vouchMessage(userId: userId, deviceId: id, identityKey: identityKey, signingKey: signingKey),
                  said,
                ) =>
          (by, said),
        _ => (null, null),
      },
      _ => (null, null),
    };

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
    // A device publishing itself again is seen first, so one back after a month
    // whose place was taken waits like a new one.
    final row = await _pool.runTx((tx) async {
      await tx.execute(_lockDevices.toSql(), parameters: {'userId': userId});
      await tx.execute(_seeDevice.toSql(), parameters: {'userId': userId, 'deviceId': id});
      return await publish(tx) ?? await publish(tx);
    });
    return switch (row) {
      null => throw _idTaken,
      {'is_full': true} => throw const Conflict(
        code: 'device_limit',
        reason: 'an account has at most $_maxDevices devices with keys, and as many waiting; remove one first',
      ),
      {'removed': true} => throw const Forbidden(code: 'device_removed', reason: 'this device was removed'),
      _ => (device: CryptoDevice.fromRow(row), added: row['added'] == true, waiting: row['waiting'] == true),
    };
  }

  @override
  Future<({CryptoDevice device, bool changed})> vouchForDevice({
    required String userId,
    required String deviceId,
    required String vouchedBy,
    required String signature,
  }) async {
    (deviceId, vouchedBy) = (deviceId.toLowerCase(), vouchedBy.toLowerCase());
    final signers = await _signersOf(userId: userId, ids: [deviceId, vouchedBy]);
    // Only a vouch that checks out goes on. One naming a device that isn't the
    // caller's in use goes on as no voucher at all, for the write to say which.
    final voucher = switch ((signers[deviceId], signers[vouchedBy])) {
      (final device?, final voucher?)
          when deviceId != vouchedBy && !device.removed && !voucher.removed && !device.waiting && !voucher.waiting =>
        switch (await voucher.signed(
          _vouchMessage(
            userId: userId,
            deviceId: deviceId,
            identityKey: device.identityKey,
            signingKey: device.signingKey,
          ),
          signature,
        )) {
          true => vouchedBy,
          false => throw _badSignature,
        },
      _ => null,
    };

    Future<Map<String, dynamic>> vouch(TxSession tx) async {
      final rows = await tx.execute(
        _vouchForDevice.toSql(),
        parameters: {'userId': userId, 'deviceId': deviceId, 'vouchedBy': voucher, 'signature': signature},
      );
      return rows.first.toColumnMap();
    }

    final row = await _pool.runTx((tx) async {
      await tx.execute(_lockDevices.toSql(), parameters: {'userId': userId});
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
      {'vouched_by': final by, 'signature': final String said} when '$by' == vouchedBy && said.sameBytes(signature) => (
        device: CryptoDevice.fromRow(row),
        changed: false,
      ),
      {'voucher_owned': false} => throw const BadRequest(reason: 'vouchedBy must be another device of yours'),
      _ => throw const Conflict(code: 'already_vouched', reason: 'this device is already vouched for'),
    };
  }

  @override
  Future<CryptoDevices> getDevices({required String readerId, required String ownerId}) async {
    final rows = await _pool.execute(_listDevices.toSql(), parameters: {'readerId': readerId, 'ownerId': ownerId});
    final maps = [
      for (final row in rows) row.toColumnMap(),
    ];
    if (maps.first['forbidden'] == true) {
      throw const Forbidden(reason: 'You do not have permission to see these devices.');
    }
    final listed = [
      for (final map in maps)
        if (map['id'] != null) (CryptoDevice.fromRow(map), map['waiting'] == true),
    ];
    return CryptoDevices(
      [
        for (final (device, waits) in listed)
          if (device.removedAt == null && !waits) device,
      ],
      removed: [
        for (final (device, _) in listed)
          if (device.removedAt != null) device,
      ],
      waiting: [
        for (final (device, waits) in listed)
          if (device.removedAt == null && waits) device,
      ],
    );
  }

  @override
  Future<({bool placed})> removeDevice({
    required String userId,
    required String deviceId,
    required String removedBy,
    required int signedAt,
    required String signature,
  }) async {
    (deviceId, removedBy) = (deviceId.toLowerCase(), removedBy.toLowerCase());
    switch ((await _signersOf(userId: userId, ids: [removedBy]))[removedBy]) {
      case null:
        throw const BadRequest(code: 'unknown_device', reason: 'removedBy must be a published device of yours');
      // a device that removed itself and asks again is told what any repeat is told
      case final signer when signer.removed && removedBy == deviceId:
        throw NotFound(type: 'Device', id: deviceId);
      case final signer when signer.removed:
        throw _removerRemoved;
      case final signer
          when !await signer.signed(
            _removalMessage(userId: userId, deviceId: deviceId, signedAt: signedAt),
            signature,
          ):
        throw _badSignature;
      case _ when !_fresh(signedAt):
        throw const BadRequest(
          code: 'signature_expired',
          reason: 'a removal is signed within ten minutes of the server\'s clock',
        );
    }
    final row = await _pool.runTx((tx) async {
      await tx.execute(_lockDevices.toSql(), parameters: {'userId': userId});
      final rows = await tx.execute(
        _removeDevice.toSql(),
        parameters: {'userId': userId, 'deviceId': deviceId, 'removedBy': removedBy},
      );
      return rows.first.toColumnMap();
    });
    switch (row) {
      case {'found': false}:
        throw NotFound(type: 'Device', id: deviceId);
      case {'remover_in_use': false}:
        throw _removerRemoved;
      case {'removed': false, 'removable_at': final DateTime at}:
        throw Forbidden(
          code: 'device_too_new',
          reason: 'a device removes one added before it once it has been in use for $_removalWaitHours hours',
          payload: {'removableAt': at.toUtc().toIso8601String()},
        );
    }
    return (placed: row['waited'] != true);
  }

  /// In seconds throughout, so a time no clock could hold is only far off.
  bool _fresh(int signedAt) {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    return (now - signedAt).abs() <= _removalWindow.inSeconds;
  }

  Future<Map<String, _Signer>> _signersOf({required String userId, required List<String> ids}) async {
    final rows = await _pool.execute(_signers.toSql(), parameters: {'userId': userId, 'ids': ids});
    return {
      for (final row in rows)
        row[0].toString(): (
          identityKey: row[1] as String,
          signingKey: row[2] as String,
          removed: row[3] as bool,
          waiting: row[4] as bool,
        ),
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
      {'sender_waiting': true} => throw _waiting,
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
    await _pool.runTx((tx) async {
      await tx.execute(_lockDevices.toSql(), parameters: {'userId': userId});
      await tx.execute(_seeDevice.toSql(), parameters: {'userId': userId, 'deviceId': deviceId});
    });
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
