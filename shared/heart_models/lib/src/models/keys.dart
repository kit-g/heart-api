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
    };
  }
}

/// A sealed item waiting for one device.
abstract interface class QueuedItem implements Model {
  String get id;

  String get recipientDeviceId;

  String? get senderDeviceId;

  /// What the item is, in the app's words.
  String get kind;

  /// Ciphertext.
  String get content;

  DateTime get createdAt;

  factory({
    required String id,
    required String recipientDeviceId,
    String? senderDeviceId,
    required String kind,
    required String content,
    required DateTime createdAt,
  }) = _QueuedItem.new;

  factory fromRow(Map row) {
    return QueuedItem(
      id: row['id'].toString(),
      recipientDeviceId: row['recipient_device_id'].toString(),
      senderDeviceId: row['sender_device_id']?.toString(),
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
  final String kind;
  @override
  final String content;
  @override
  final DateTime createdAt;

  const new({
    required this.id,
    required this.recipientDeviceId,
    this.senderDeviceId,
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
  final List<CryptoDevice> devices;

  const new(this.devices);

  /// A device this build can't read is left out.
  factory fromJson(Map json) => CryptoDevices(readIndexed(json['devices'], CryptoDevice.fromJson).items);

  @override
  Map<String, dynamic> toMap() => {
    'devices': [for (final device in devices) device.toMap()],
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
