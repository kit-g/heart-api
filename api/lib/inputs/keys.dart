part of 'inputs.dart';

const _maxPublicKey = 128;

/// `POST /keys/devices`.
class DevicePublishIn {
  final String id;
  final String identityKey;
  final String signingKey;
  final String fallbackKey;
  final String? signature;
  final String? vouchedBy;

  const new _({
    required this.id,
    required this.identityKey,
    required this.signingKey,
    required this.fallbackKey,
    this.signature,
    this.vouchedBy,
  });

  static Future<DevicePublishIn> fromRequest(Request req) async {
    final json = await req.json();
    final id = json.string('id');
    if (!isUuidV7(id)) throw const BadRequest(reason: 'id must be a UUIDv7');
    // a vouch is a device and its signature, or nothing: either one alone would
    // show a device as vouched for when nobody signed
    final (signature, vouchedBy) = switch ((json.stringOrNull('signature', maxLength: 256), json['vouchedBy'])) {
      (null, null) => (null, null),
      (final String signature, final String device) when isUuidV7(device) => (signature, device),
      _ => throw const BadRequest(reason: 'a vouch is a signature and the id of the device that made it'),
    };
    return DevicePublishIn._(
      id: id,
      identityKey: json.string('identityKey', maxLength: _maxPublicKey),
      signingKey: json.string('signingKey', maxLength: _maxPublicKey),
      fallbackKey: json.string('fallbackKey', maxLength: _maxPublicKey),
      signature: signature,
      vouchedBy: vouchedBy,
    );
  }
}

/// `PUT /keys/devices/:deviceId/fallback` — `{key}`.
class FallbackKeyIn {
  final String key;

  const new _(this.key);

  static Future<FallbackKeyIn> fromRequest(Request req) async {
    return FallbackKeyIn._((await req.json()).string('key', maxLength: _maxPublicKey));
  }
}

/// `POST /keys/devices/:deviceId/one-time-keys` — `{keys: {id: key}}`, no more
/// at once than a device can hold.
class OneTimeKeysIn {
  final Map<String, String> keys;

  const new _(this.keys);

  static bool _isKey(MapEntry entry) {
    return switch ((entry.key, entry.value)) {
      (final String id, final String public) =>
        id.isNotEmpty && id.length <= 64 && public.isNotEmpty && public.length <= _maxPublicKey,
      _ => false,
    };
  }

  static Future<OneTimeKeysIn> fromRequest(Request req) async {
    final json = await req.json();
    return switch (json['keys']) {
      final Map keys when keys.isNotEmpty && keys.length <= 50 && keys.entries.every(_isKey) => OneTimeKeysIn._(
        Map.of(keys.cast<String, String>()),
      ),
      _ => throw const BadRequest(reason: 'keys must map a name to a key, at most 50 of them'),
    };
  }
}

/// `POST /keys/queue` — one sealed item for one device.
class EnqueueIn {
  final String id;
  final String recipientDeviceId;
  final String senderDeviceId;
  final String kind;
  final String content;

  const new _({
    required this.id,
    required this.recipientDeviceId,
    required this.senderDeviceId,
    required this.kind,
    required this.content,
  });

  static final _kind = RegExp(r'^[a-z][a-z0-9_]{0,31}$');

  static Future<EnqueueIn> fromRequest(Request req) async {
    final json = await req.json();
    String device(String field) {
      final id = json.string(field);
      if (!isUuidV7(id)) throw BadRequest(reason: '$field must be a device id');
      return id;
    }

    final id = json.string('id');
    if (!isUuidV7(id)) throw const BadRequest(reason: 'id must be a UUIDv7');
    final kind = json.string('kind');
    if (!_kind.hasMatch(kind)) throw const BadRequest(reason: 'kind must be a snake_case word');
    // A string and nothing else, so nothing readable can ride in structure.
    final content = switch (json['content']) {
      final String content when content.isNotEmpty && content.length <= 1024 => content,
      _ => throw const BadRequest(reason: 'content must be text of at most 1 KB'),
    };
    return EnqueueIn._(
      id: id,
      recipientDeviceId: device('recipientDeviceId'),
      senderDeviceId: device('senderDeviceId'),
      kind: kind,
      content: content,
    );
  }
}

/// `GET /keys/queue` — `?deviceId=`, a device of the caller's.
class QueueQuery {
  final String deviceId;

  const new _(this.deviceId);

  factory fromRequest(Request req) {
    return switch (req.url.queryParameters['deviceId']) {
      final String id when isUuidV7(id) => QueueQuery._(id),
      _ => throw const BadRequest(reason: 'deviceId must be a device id'),
    };
  }
}

/// `POST /keys/queue/confirmations` — `{deviceId, ids}`.
class QueueConfirmIn {
  final String deviceId;
  final List<String> ids;

  const new _({required this.deviceId, required this.ids});

  static Future<QueueConfirmIn> fromRequest(Request req) async {
    final json = await req.json();
    final deviceId = json.string('deviceId');
    if (!isUuidV7(deviceId)) throw const BadRequest(reason: 'deviceId must be a device id');
    return switch (json['ids']) {
      final List ids when ids.length <= 500 && ids.every((id) => id is String && isUuidV7(id)) => QueueConfirmIn._(
        deviceId: deviceId,
        ids: ids.cast<String>(),
      ),
      _ => throw const BadRequest(reason: 'ids must be a list of at most 500 item ids'),
    };
  }
}
