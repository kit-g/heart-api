import 'package:heart/middleware/database.dart';
import 'package:heart/notifications/notifier.dart';
import 'package:heart/notifications/topics.dart';
import 'package:relic/relic.dart';

/// The evening's hour a daily push goes out at, in the person's own time.
const _digestHour = 18;

/// Consumes a `push.requested` event off the API's events queue: a route asks for
/// a push and gets on with answering. An unknown topic is a message from a newer
/// deploy during a rollout, and is dropped.
Future<void> pushRequested(Request req, Map event) async {
  final topic = PushTopic.of(event['topic'] as String);
  if (topic == null) return;
  await req.notify(
    userId: event['userId'] as String,
    topic: topic,
    name: event['name'] as String?,
    data: {
      for (final MapEntry(:key, :value) in ((event['data'] as Map?) ?? const {}).entries) '$key': '$value',
    },
    connectionId: event['connectionId'] as String?,
    actorId: event['actorId'] as String?,
  );
}

/// The hourly schedule: sends what's owed to people whose evening it is.
Future<void> deliverDigests(Request req) async {
  final due = await req.pushService.claimDueDigests(localHour: _digestHour);
  for (final (:userId, :topic) in due) {
    if (PushTopic.of(topic) case final PushTopic known) {
      await req.deliverDigest(userId: userId, topic: known);
    }
  }
}
