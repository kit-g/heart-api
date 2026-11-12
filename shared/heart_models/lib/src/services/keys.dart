import '../models/keys.dart';

abstract interface class KeyService {
  /// Publishes a device, idempotent on its id. [signature] and [vouchedBy] say
  /// another device of the owner's vouched for it, and [vouchedBy] has to be theirs.
  Future<CryptoDevice> publishDevice({
    required String userId,
    required String id,
    required String identityKey,
    required String signingKey,
    required String fallbackKey,
    String? signature,
    String? vouchedBy,
  });

  /// Attaches a vouch to a device of the caller's that already published: [vouchedBy],
  /// another device of theirs in use, signed it. A device is vouched for once; the
  /// same vouch again changes nothing, and `changed` says whether this one did.
  Future<({CryptoDevice device, bool changed})> vouchForDevice({
    required String userId,
    required String deviceId,
    required String vouchedBy,
    required String signature,
  });

  /// [ownerId]'s devices in use. Throws unless [readerId] shares keys with them.
  Future<List<CryptoDevice>> getDevices({required String readerId, required String ownerId});

  /// Stops using a device of the caller's: nothing more is sent to it.
  Future<void> removeDevice({required String userId, required String deviceId});

  Future<void> replaceFallbackKey({required String userId, required String deviceId, required String key});

  /// Adds single-use keys to a device of the caller's, and answers how many it
  /// holds. Throws if it would hold more than the limit.
  Future<int> addOneTimeKeys({
    required String userId,
    required String deviceId,
    required Map<String, String> keys,
  });

  Future<int> countOneTimeKeys({required String userId, required String deviceId});

  /// One single-use key from each of [ownerId]'s devices, or only from those of
  /// them [deviceIds] names, none handed out twice. A device with none left answers
  /// its fallback key. A named device that isn't theirs, or is removed, is left out.
  Future<List<CryptoDevice>> claimKeys({required String claimerId, required String ownerId, List<String>? deviceIds});

  /// Sends a sealed item to one device. `delivered` is `false` if this id had
  /// already arrived. `notify` names the account to wake: the recipient's, when this
  /// item arrived and nothing else reached that device in the last minute.
  Future<({bool delivered, String? notify})> enqueue({
    required String userId,
    required String id,
    required String recipientDeviceId,
    required String senderDeviceId,
    required String kind,
    required String content,
  });

  /// What waits for a device of the caller's, oldest first.
  Future<List<QueuedItem>> getQueue({required String userId, required String deviceId, int limit = 100});

  /// Drops what a device has safely received.
  Future<void> confirm({required String userId, required String deviceId, required List<String> ids});

  /// Who to tell when [userId]'s devices change: everyone who shares keys with them.
  Future<List<String>> getKeyPeers({required String userId});
}
