import 'package:heart/core/handler.dart';
import 'package:heart/globals/config.dart';
import 'package:heart/globals/globals.dart';
import 'package:heart/inputs/inputs.dart';
import 'package:heart/middleware/database.dart';
import 'package:heart/middleware/events.dart';
import 'package:heart/models/errors.dart';
import 'package:heart_models/heart_models.dart';
import 'package:heart/notifications/topics.dart';
import 'package:logging/logging.dart' as logging;
import 'package:relic/relic.dart';

final _logger = logging.Logger('Keys');

Future<void> _tellPeers(Request req) {
  return req.events.publish(
    queueUrl: req.config.eventsQueueUrl,
    message: {'type': 'devices.changed', 'userId': req.userId},
  );
}

/// A silent push: the recipient's app reads its queue. The item is stored by now and
/// is read on the app's next start anyway, so a push that can't go out doesn't turn
/// a delivered item into an error a sender would retry.
Future<void> _wake(Request req, {required String userId, required String deviceId}) async {
  try {
    await req.events.publish(
      queueUrl: req.config.eventsQueueUrl,
      message: {
        'type': 'push.requested',
        'userId': userId,
        'topic': PushTopic.queueWaiting.key,
        'actorId': req.userId,
        'data': {'deviceId': deviceId},
      },
    );
  } catch (error, stack) {
    _logger.warning('could not wake the device $deviceId', error, stack);
  }
}

/// A device in the path is one of the caller's, by an id it chose, so anything
/// that can't be such an id is no device.
String _deviceId(Request req) {
  return switch (req.rawPathParameters[#deviceId]) {
    final String id when isUuidV7(id) => id,
    final id => throw NotFound(type: 'Device', id: '$id'),
  };
}

Future<Model> publishDevice(Request req) async {
  final input = await DevicePublishIn.fromRequest(req);
  final device = await req.keyService.publishDevice(
    userId: req.userId,
    id: input.id,
    identityKey: input.identityKey,
    signingKey: input.signingKey,
    fallbackKey: input.fallbackKey,
    signature: input.signature,
    vouchedBy: input.vouchedBy,
  );
  await _tellPeers(req);
  return Created(device);
}

Future<CryptoDevice> vouchForDevice(Request req) async {
  final input = await DeviceVouchIn.fromRequest(req);
  final (:device, :changed) = await req.keyService.vouchForDevice(
    userId: req.userId,
    deviceId: _deviceId(req),
    vouchedBy: input.vouchedBy,
    signature: input.signature,
  );
  if (changed) await _tellPeers(req);
  return device;
}

Future<CryptoDevices> getDevices(Request req) async {
  final owner = req.url.queryParameters['userId'] ?? req.userId;
  return CryptoDevices(await req.keyService.getDevices(readerId: req.userId, ownerId: owner));
}

Future<Model> removeDevice(Request req) async {
  await req.keyService.removeDevice(userId: req.userId, deviceId: _deviceId(req));
  await _tellPeers(req);
  throw const NoContent();
}

Future<Model> replaceFallbackKey(Request req) async {
  final input = await FallbackKeyIn.fromRequest(req);
  await req.keyService.replaceFallbackKey(
    userId: req.userId,
    deviceId: _deviceId(req),
    key: input.key,
  );
  throw const NoContent();
}

Future<OneTimeKeyCount> addOneTimeKeys(Request req) async {
  final input = await OneTimeKeysIn.fromRequest(req);
  final count = await req.keyService.addOneTimeKeys(
    userId: req.userId,
    deviceId: _deviceId(req),
    keys: input.keys,
  );
  return OneTimeKeyCount(count);
}

Future<OneTimeKeyCount> countOneTimeKeys(Request req) async {
  final count = await req.keyService.countOneTimeKeys(
    userId: req.userId,
    deviceId: _deviceId(req),
  );
  return OneTimeKeyCount(count);
}

Future<CryptoDevices> claimKeys(Request req) async {
  final owner = req.rawPathParameters[#ownerId]!;
  final input = await ClaimKeysIn.fromRequest(req);
  return CryptoDevices(
    await req.keyService.claimKeys(claimerId: req.userId, ownerId: owner, deviceIds: input.deviceIds),
  );
}

Future<Model> enqueue(Request req) async {
  final input = await EnqueueIn.fromRequest(req);
  final (delivered: _, :notify) = await req.keyService.enqueue(
    userId: req.userId,
    id: input.id,
    recipientDeviceId: input.recipientDeviceId,
    senderDeviceId: input.senderDeviceId,
    kind: input.kind,
    content: input.content,
  );
  if (notify != null) await _wake(req, userId: notify, deviceId: input.recipientDeviceId);
  throw const NoContent();
}

Future<QueuedItems> getQueue(Request req) async {
  final query = QueueQuery.fromRequest(req);
  return QueuedItems(await req.keyService.getQueue(userId: req.userId, deviceId: query.deviceId));
}

Future<Model> confirmQueued(Request req) async {
  final input = await QueueConfirmIn.fromRequest(req);
  await req.keyService.confirm(userId: req.userId, deviceId: input.deviceId, ids: input.ids);
  throw const NoContent();
}
