part of 'inputs.dart';

/// A topic a person can change, or not one at all.
PushTopic _settableTopic(String key) {
  return switch (PushTopic.of(key)) {
    final PushTopic topic when !topic.silent => topic,
    _ => throw NotFound(type: 'Push topic', id: key),
  };
}

String? _connectionIdOrNull(Object? id) {
  return switch (id) {
    null => null,
    final String id when isUuidV7(id) => id,
    _ => throw const BadRequest(reason: 'connectionId must be a connection\'s id'),
  };
}

/// `PUT /push/settings/:topic` — `{delivery, connectionId?}`. `connectionId` makes
/// it about one relationship rather than the whole topic.
class PushPreferenceIn {
  final PushTopic topic;
  final String delivery;
  final String? connectionId;

  const new _({required this.topic, required this.delivery, this.connectionId});

  static Future<PushPreferenceIn> fromRequest(Request req, {required String topicKey}) async {
    final json = await req.json();
    final topic = _settableTopic(topicKey);
    final delivery = json.string('delivery');
    if (!topic.options.contains(delivery)) {
      throw BadRequest(code: 'invalid_delivery', reason: '$topicKey can be ${topic.options.join(', ')}');
    }
    return PushPreferenceIn._(
      topic: topic,
      delivery: delivery,
      connectionId: _connectionIdOrNull(json['connectionId']),
    );
  }
}

/// `DELETE /push/settings/:topic` — `?connectionId=` for one relationship rather
/// than the whole topic.
class PushPreferenceClearQuery {
  final PushTopic topic;
  final String? connectionId;

  const new _({required this.topic, this.connectionId});

  factory fromRequest(Request req, {required String topicKey}) {
    return PushPreferenceClearQuery._(
      topic: _settableTopic(topicKey),
      connectionId: _connectionIdOrNull(req.url.queryParameters['connectionId']),
    );
  }
}
