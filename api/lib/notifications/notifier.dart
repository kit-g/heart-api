import 'package:heart/globals/config.dart';
import 'package:heart/middleware/database.dart';
import 'package:heart/middleware/events.dart';
import 'package:heart/notifications/renderer.dart';
import 'package:heart/notifications/topics.dart';
import 'package:relic/relic.dart';

/// The one way a push leaves the API.
///
/// It says who, never what. There is a [name] and nothing else to put in the
/// words, because a push goes through Apple and Google, so no message text,
/// weights or health values can reach one. [data] carries ids for the app.
extension Notifier on Request {
  /// Sends [topic] to [userId], as they want it. [actorId] is who it's about, and
  /// nothing goes across a block. [variant] picks a topic's wording.
  Future<void> notify({
    required String userId,
    required PushTopic topic,
    String? name,
    String variant = 'title',
    Map<String, String> data = const {},
    String? connectionId,
    String? actorId,
  }) async {
    final audience = await pushService.getPushAudience(
      userId: userId,
      topic: topic.key,
      connectionId: connectionId,
      actorId: actorId,
    );
    if (audience.blocked || audience.devices.isEmpty) return;

    final delivery = switch (topic.silent) {
      true => PushTopic.instant,
      false => topic.deliveryFor(forPerson: audience.forPerson, forTopic: audience.forTopic),
    };
    switch (delivery) {
      case PushTopic.off:
        return;
      case PushTopic.daily:
        await pushService.queueDigest(userId: userId, topic: topic.key);
        return;
    }

    await _sendPush(devices: audience.devices, topic: topic, name: name, variant: variant, data: data);
  }

  /// What the daily job calls for a digest it claimed: [userId] may have turned
  /// the topic off since it was queued. A digest doesn't know whose activity
  /// queued it, so it goes while the topic, or any one person, still wants it.
  Future<void> deliverDigest({required String userId, required PushTopic topic}) async {
    final said = [
      for (final preference in await pushService.getPushPreferences(userId: userId))
        if (preference.topic == topic.key) preference,
    ];
    final forTopic = [
      for (final preference in said)
        if (preference.connectionId == null) preference.delivery,
    ].firstOrNull;
    final wanted = [
      topic.deliveryFor(forTopic: forTopic),
      for (final preference in said)
        if (preference.connectionId != null) topic.deliveryFor(forPerson: preference.delivery, forTopic: forTopic),
    ].any((delivery) => delivery != PushTopic.off);
    if (!wanted) return;

    final audience = await pushService.getPushAudience(userId: userId, topic: topic.key);
    await _sendPush(devices: audience.devices, topic: topic);
  }

  Future<void> _sendPush({
    required List<({String token, String locale})> devices,
    required PushTopic topic,
    String? name,
    String variant = 'title',
    Map<String, String> data = const {},
  }) async {
    // A silent push has no words, so every device gets the one message.
    final byLocale = <String, List<String>>{};
    for (final device in devices) {
      byLocale.putIfAbsent(topic.silent ? config.defaultLocale : device.locale, () => []).add(device.token);
    }

    for (final MapEntry(key: locale, value: tokens) in byLocale.entries) {
      await this.events.publish(
        queueUrl: config.firebaseEventsQueueUrl,
        message: {
          'type': 'push.notification',
          'tokens': tokens,
          if (topic.silent)
            'silent': true
          else
            'title': renderTitle(
              locale: locale,
              eventType: topic.key,
              variant: variant,
              args: {'name': name.orSomeone(locale, defaultLocale: config.defaultLocale)},
              defaultLocale: config.defaultLocale,
            ),
          'channel': ?topic.channel,
          if (topic.collapses) 'collapseKey': topic.key,
          'data': {'topic': topic.key, ...data},
        },
      );
    }
  }
}

extension on String? {
  /// Someone with no name still reads as a person, in the push's own language.
  String orSomeone(String locale, {required String defaultLocale}) {
    return switch (this) {
      final String name when name.trim().isNotEmpty => name,
      _ => renderTitle(
        locale: locale,
        eventType: 'person',
        variant: 'unnamed',
        args: const {},
        defaultLocale: defaultLocale,
      ),
    };
  }
}
