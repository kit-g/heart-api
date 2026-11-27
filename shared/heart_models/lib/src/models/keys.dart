import 'misc.dart';
import 'tolerant.dart';

/// A device's public keys, which is all the server ever holds of its encryption.
abstract interface class CryptoDevice implements Model {
  String get id;

  String get userId;

  String get identityKey;

  String get signingKey;

  String get fallbackKey;

  /// A signature from another device of the owner's, if one vouched for this one.
  String? get signature;

  String? get vouchedBy;

  DateTime get createdAt;

  /// A single-use key, when this answers a claim and one was left. Without one,
  /// [fallbackKey] is the one to use.
  String? get oneTimeKeyId;

  String? get oneTimeKey;

  /// When its owner removed it, on a device of theirs listed as removed.
  DateTime? get removedAt;

  /// Which of the owner's devices removed it; null for one removed before the server
  /// recorded that.
  String? get removedBy;

  /// The day, in UTC, it last reached the server; only on the owner's own list.
  DateTime? get lastSeenOn;

  factory({
    required String id,
    required String userId,
    required String identityKey,
    required String signingKey,
    required String fallbackKey,
    String? signature,
    String? vouchedBy,
    required DateTime createdAt,
    String? oneTimeKeyId,
    String? oneTimeKey,
    DateTime? removedAt,
    String? removedBy,
    DateTime? lastSeenOn,
  }) = _CryptoDevice.new;

  factory fromRow(Map row) {
    return CryptoDevice(
      id: row['id'].toString(),
      userId: row['user_id'] as String,
      identityKey: row['identity_key'] as String,
      signingKey: row['signing_key'] as String,
      fallbackKey: row['fallback_key'] as String,
      signature: row['signature'] as String?,
      vouchedBy: row['vouched_by']?.toString(),
      createdAt: row['created_at'] as DateTime,
      oneTimeKeyId: row['key_id'] as String?,
      oneTimeKey: row['key'] as String?,
      removedAt: row['removed_at'] as DateTime?,
      removedBy: row['removed_by']?.toString(),
      lastSeenOn: switch (row['seen_on']) {
        final DateTime on => DateTime.utc(on.year, on.month, on.day),
        _ => null,
      },
    );
  }

  factory fromJson(Map json) {
    return CryptoDevice(
      id: json['id'] as String,
      userId: json['userId'] as String,
      identityKey: json['identityKey'] as String,
      signingKey: json['signingKey'] as String,
      fallbackKey: json['fallbackKey'] as String,
      signature: json['signature'] as String?,
      vouchedBy: json['vouchedBy'] as String?,
      createdAt: DateTime.parse(json['createdAt'] as String),
      oneTimeKeyId: json['oneTimeKeyId'] as String?,
      oneTimeKey: json['oneTimeKey'] as String?,
      removedAt: switch (json['removedAt']) {
        final String at => DateTime.parse(at),
        _ => null,
      },
      removedBy: json['removedBy'] as String?,
      lastSeenOn: switch (json['lastSeenOn']) {
        final String on => switch (DateTime.parse(on)) {
          final day => DateTime.utc(day.year, day.month, day.day),
        },
        _ => null,
      },
    );
  }
}

class _CryptoDevice implements CryptoDevice {
  @override
  final String id;
  @override
  final String userId;
  @override
  final String identityKey;
  @override
  final String signingKey;
  @override
  final String fallbackKey;
  @override
  final String? signature;
  @override
  final String? vouchedBy;
  @override
  final DateTime createdAt;
  @override
  final String? oneTimeKeyId;
  @override
  final String? oneTimeKey;
  @override
  final DateTime? removedAt;
  @override
  final String? removedBy;
  @override
  final DateTime? lastSeenOn;

  const new({
    required this.id,
    required this.userId,
    required this.identityKey,
    required this.signingKey,
    required this.fallbackKey,
    this.signature,
    this.vouchedBy,
    required this.createdAt,
    this.oneTimeKeyId,
    this.oneTimeKey,
    this.removedAt,
    this.removedBy,
    this.lastSeenOn,
  });

  @override
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'userId': userId,
      'identityKey': identityKey,
      'signingKey': signingKey,
      'fallbackKey': fallbackKey,
      'signature': ?signature,
      'vouchedBy': ?vouchedBy,
      'createdAt': createdAt.toIso8601String(),
      'oneTimeKeyId': ?oneTimeKeyId,
      'oneTimeKey': ?oneTimeKey,
      'removedAt': ?removedAt?.toIso8601String(),
      'removedBy': ?removedBy,
      'lastSeenOn': ?lastSeenOn?.toYmd(),
    };
  }
}

extension on DateTime {
  /// `2026-11-26`.
  String toYmd() => [
    year.toString().padLeft(4, '0'),
    month.toString().padLeft(2, '0'),
    day.toString().padLeft(2, '0'),
  ].join('-');
}

/// A sealed item waiting for one device.
abstract interface class QueuedItem implements Model {
  String get id;

  String get recipientDeviceId;

  String? get senderDeviceId;

  /// The account that sent it, as the server knows it, so the recipient can check
  /// the sending device against that account's devices without trusting what the
  /// item says. Null once that account is deleted.
  String? get senderUserId;

  /// What the item is, in the app's words.
  String get kind;

  /// Ciphertext.
  String get content;

  DateTime get createdAt;

  factory({
    required String id,
    required String recipientDeviceId,
    String? senderDeviceId,
    String? senderUserId,
    required String kind,
    required String content,
    required DateTime createdAt,
  }) = _QueuedItem.new;

  factory fromRow(Map row) {
    return QueuedItem(
      id: row['id'].toString(),
      recipientDeviceId: row['recipient_device_id'].toString(),
      senderDeviceId: row['sender_device_id']?.toString(),
      senderUserId: row['sender_user_id'] as String?,
      kind: row['kind'] as String,
      content: row['content'] as String,
      createdAt: row['created_at'] as DateTime,
    );
  }

  factory fromJson(Map json) {
    return QueuedItem(
      id: json['id'] as String,
      recipientDeviceId: json['recipientDeviceId'] as String,
      senderDeviceId: json['senderDeviceId'] as String?,
      senderUserId: json['senderUserId'] as String?,
      kind: json['kind'] as String,
      content: json['content'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }
}

class _QueuedItem implements QueuedItem {
  @override
  final String id;
  @override
  final String recipientDeviceId;
  @override
  final String? senderDeviceId;
  @override
  final String? senderUserId;
  @override
  final String kind;
  @override
  final String content;
  @override
  final DateTime createdAt;

  const new({
    required this.id,
    required this.recipientDeviceId,
    this.senderDeviceId,
    this.senderUserId,
    required this.kind,
    required this.content,
    required this.createdAt,
  });

  @override
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'recipientDeviceId': recipientDeviceId,
      'senderDeviceId': ?senderDeviceId,
      'senderUserId': ?senderUserId,
      'kind': kind,
      'content': content,
      'createdAt': createdAt.toIso8601String(),
    };
  }
}

/// How many single-use keys a device holds.
class OneTimeKeyCount implements Model {
  final int count;

  const new(this.count);

  factory fromJson(Map json) => OneTimeKeyCount((json['count'] as num).toInt());

  @override
  Map<String, dynamic> toMap() => {'count': count};
}

/// A list of devices, answered by a device list and by a claim.
class CryptoDevices implements Model {
  /// The devices in use.
  final List<CryptoDevice> devices;

  /// The owner's own devices removed lately, newest removal first, each saying when
  /// and by which device, so a removal the owner didn't make shows. Only on the
  /// owner's own list; never anything to send to.
  final List<CryptoDevice> removed;

  /// The owner's own devices that asked to publish while the account was full, each
  /// holding no place: never a device to send to.
  final List<CryptoDevice> waiting;

  const new(this.devices, {this.removed = const [], this.waiting = const []});

  /// A device this build can't read is left out.
  factory fromJson(Map json) => CryptoDevices(
    readIndexed(json['devices'], CryptoDevice.fromJson).items,
    removed: readIndexed(json['removed'], CryptoDevice.fromJson).items,
    waiting: readIndexed(json['waiting'], CryptoDevice.fromJson).items,
  );

  @override
  Map<String, dynamic> toMap() => {
    'devices': [for (final device in devices) device.toMap()],
    if (removed.isNotEmpty) 'removed': [for (final device in removed) device.toMap()],
    if (waiting.isNotEmpty) 'waiting': [for (final device in waiting) device.toMap()],
  };
}

/// What waits for a device. Empty once it has confirmed everything.
class QueuedItems implements Model {
  final List<QueuedItem> items;

  const new(this.items);

  /// An item this build can't read is left out.
  factory fromJson(Map json) => QueuedItems(readIndexed(json['items'], QueuedItem.fromJson).items);

  @override
  Map<String, dynamic> toMap() => {
    'items': [for (final item in items) item.toMap()],
  };
}
