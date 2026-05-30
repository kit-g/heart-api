import 'package:heart/globals/config.dart';
import 'package:heart/middleware/database.dart';
import 'package:heart/middleware/events.dart';
import 'package:heart/notifications/renderer.dart';
import 'package:relic/relic.dart';

/// Consumes a `comment.created` event off the API's events queue:
///  - looks up the owner's registered device tokens + their locales,
///  - groups tokens by locale,
///  - renders a localized title per group from the notifications templates,
///  - enqueues one `push.notification` event per locale to the firebase queue.
///
/// The firebase service stays a dumb pipe: by the time the message reaches it,
/// the copy is fully baked and no DB or template logic is needed.
Future<void> commentNotification(Request req, Map event) async {
  final ownerId = event['ownerId'] as String;
  final authorName = event['authorName'] as String;
  final targetType = event['targetType'] as String;
  final commentId = event['commentId'] as String;
  final targetId = event['targetId'] as String;
  final body = event['body'] as String;

  final devices = await req.deviceService.tokensWithLocale(ownerId);
  if (devices.isEmpty) return;

  final byLocale = <String, List<String>>{};
  for (final d in devices) {
    byLocale.putIfAbsent(d.locale, () => []).add(d.token);
  }

  for (final MapEntry(key: locale, value: tokens) in byLocale.entries) {
    final title = renderTitle(
      locale: locale,
      eventType: 'comment.created',
      variant: targetType,
      args: {'author': authorName},
      defaultLocale: req.config.defaultLocale,
    );
    await req.events.publish(
      queueUrl: req.config.firebaseEventsQueueUrl,
      message: {
        'type': 'push.notification',
        'tokens': tokens,
        'title': title,
        'body': body,
        'data': {
          'commentId': commentId,
          'targetType': targetType,
          'targetId': targetId,
        },
      },
    );
  }
}
