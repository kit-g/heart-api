import 'package:heart/core/request.dart';
import 'package:heart/globals/config.dart';
import 'package:heart/globals/globals.dart';
import 'package:heart/inputs/inputs.dart';
import 'package:heart/middleware/database.dart';
import 'package:heart/models/errors.dart';
import 'package:heart/notifications/renderer.dart';
import 'package:heart/notifications/topics.dart';
import 'package:heart_models/heart_models.dart';
import 'package:relic/relic.dart';

/// The whole catalog in the caller's language, so the app can draw its screen
/// from the answer and a topic it has never heard of still shows up.
Future<PushSettings> getPushSettings(Request req) async {
  final said = await req.pushService.getPushPreferences(userId: req.userId);
  final forTopic = {
    for (final preference in said)
      if (preference.connectionId == null) preference.topic: preference.delivery,
  };
  final locale = req.locale(req.config.supportedLocales, req.config.defaultLocale);
  String copy(PushTopic topic, String variant) {
    return renderTitle(
      locale: locale,
      eventType: topic.key,
      variant: variant,
      args: const {},
      defaultLocale: req.config.defaultLocale,
    );
  }

  return PushSettings(
    topics: [
      for (final topic in PushTopic.settable)
        PushSetting(
          topic: topic.key,
          group: topic.group,
          name: copy(topic, 'name'),
          description: copy(topic, 'description'),
          delivery: topic.deliveryFor(forTopic: forTopic[topic.key]),
          options: topic.options,
          perPersonAs: [for (final role in topic.perPersonAs) role.name],
        ),
    ],
    forPeople: [
      for (final preference in said)
        if (preference.connectionId != null) preference,
    ],
  );
}

Future<Model> setPushPreference(Request req) async {
  final input = await PushPreferenceIn.fromRequest(req, topicKey: req.rawPathParameters[#topic]!);
  await req.pushService.setPushPreference(
    userId: req.userId,
    topic: input.topic.key,
    delivery: input.delivery,
    connectionId: input.connectionId,
  );
  throw const NoContent();
}

Future<Model> clearPushPreference(Request req) async {
  final query = PushPreferenceClearQuery.fromRequest(req, topicKey: req.rawPathParameters[#topic]!);
  await req.pushService.clearPushPreference(
    userId: req.userId,
    topic: query.topic.key,
    connectionId: query.connectionId,
  );
  throw const NoContent();
}
