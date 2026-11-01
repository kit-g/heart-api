import 'package:heart/notifications/notifier.dart';
import 'package:relic/relic.dart';

/// Consumes a `comment.created` event off the API's events queue. It says who
/// commented and on what kind of thing; the text stays out of the push.
Future<void> commentNotification(Request req, Map event) async {
  final targetType = event['targetType'] as String;
  await req.notify(
    userId: event['ownerId'] as String,
    topic: .commentCreated,
    name: event['authorName'] as String,
    variant: targetType,
    actorId: event['authorId'] as String?,
    data: {
      'commentId': event['commentId'] as String,
      'targetType': targetType,
      'targetId': event['targetId'] as String,
    },
  );
}
