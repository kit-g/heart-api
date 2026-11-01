part of 'inputs.dart';

/// `PUT /push/settings/:topic` — `{delivery, connectionId?}`. `connectionId` makes
/// it about one relationship rather than the whole topic.
class PushPreferenceIn {
  final PushTopic topic;
  final String delivery;
  final String? connectionId;

  const new _({required this.topic, required this.delivery, this.connectionId});

  static Future<PushPreferenceIn> fromRequest(Request req, {required String topicKey}) async {
    final json = await req.json();
    final topic = PushTopic.of(topicKey);
    if (topic == null || topic.silent) {
      throw NotFound(type: 'Push topic', id: topicKey);
    }
    final delivery = json.string('delivery');
    if (!topic.options.contains(delivery)) {
      throw BadRequest(code: 'invalid_delivery', reason: '$topicKey can be ${topic.options.join(', ')}');
    }
    return PushPreferenceIn._(
      topic: topic,
      delivery: delivery,
      connectionId: switch (json['connectionId']) {
        null => null,
        final String id when isUuidV7(id) => id,
        _ => throw const BadRequest(reason: 'connectionId must be a connection\'s id'),
      },
    );
  }
}
