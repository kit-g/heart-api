part of 'inputs.dart';

String _publicKey(Map<String, dynamic> json, String field) {
  final key = json.string(field);
  if (key.isEmpty || key.length > 128) throw BadRequest(reason: '$field must be a public key');
  return key;
}

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
    return DevicePublishIn._(
      id: id,
      identityKey: _publicKey(json, 'identityKey'),
      signingKey: _publicKey(json, 'signingKey'),
      fallbackKey: _publicKey(json, 'fallbackKey'),
      signature: switch (json['signature']) {
        null => null,
        final String signature when signature.length <= 256 => signature,
        _ => throw const BadRequest(reason: 'signature must be text of at most 256 characters'),
      },
      vouchedBy: switch (json['vouchedBy']) {
        null => null,
        final String device when isUuidV7(device) => device,
        _ => throw const BadRequest(reason: 'vouchedBy must be a device id'),
      },
    );
  }
}

/// `PUT /keys/devices/:deviceId/fallback` — `{key}`.
class FallbackKeyIn {
  final String key;

  const new _(this.key);

  static Future<FallbackKeyIn> fromRequest(Request req) async {
    return FallbackKeyIn._(_publicKey(await req.json(), 'key'));
  }
}

/// `POST /keys/devices/:deviceId/one-time-keys` — `{keys: {id: key}}`.
class OneTimeKeysIn {
  final Map<String, String> keys;

  const new _(this.keys);

  static Future<OneTimeKeysIn> fromRequest(Request req) async {
    final json = await req.json();
    return switch (json['keys']) {
      final Map keys when keys.isNotEmpty && keys.length <= 100 => OneTimeKeysIn._({
        for (final MapEntry(:key, :value) in keys.entries)
          switch ((key, value)) {
            (final String id, final String _) when id.isNotEmpty && id.length <= 64 => id,
            _ => throw const BadRequest(reason: 'keys must map a name to a key'),
          }: switch (value) {
            final String public when public.isNotEmpty && public.length <= 128 => public,
            _ => throw const BadRequest(reason: 'keys must map a name to a key'),
          },
      }),
      _ => throw const BadRequest(reason: 'keys must map a name to a key'),
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
