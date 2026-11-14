import 'package:heart/middleware/database.dart';
import 'package:heart/notifications/notifier.dart';
import 'package:relic/relic.dart';

/// Consumes a `devices.changed` event: everyone who shares keys with this person
/// looks again at their devices, and their app says so in the thread. So do the
/// person's own devices, so another phone of theirs can trust a new key or flag
/// one they didn't add.
Future<void> devicesChanged(Request req, Map event) async {
  final userId = event['userId'] as String;
  final peers = await req.keyService.getKeyPeers(userId: userId);
  for (final peer in {userId, ...peers}) {
    await req.notify(userId: peer, topic: .devicesChanged, actorId: userId, data: {'userId': userId});
  }
}
