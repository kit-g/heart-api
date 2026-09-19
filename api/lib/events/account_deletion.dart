import 'package:heart/globals/config.dart';
import 'package:heart/middleware/apple.dart';
import 'package:heart/middleware/database.dart';
import 'package:heart/middleware/events.dart';
import 'package:heart/middleware/s3.dart';
import 'package:heart/models/apple.dart';
import 'package:relic/relic.dart';

Future<void> accountDeletion(Request request, String userId) async {
  // The grant lives on the profile row this handler is about to delete, so it
  // is read before anything else happens rather than returned from the delete.
  final appleGrant = await request.profileService.getAppleGrant(userId: userId);

  // Delete workout images from S3 before the DB cascade removes the records.
  // S3 DELETE is idempotent so retries are safe.
  final keys = await request.imageDbService.getUserImageKeys(userId: userId);
  for (final key in keys) {
    await request.imageStorageService.deleteObject(key: key);
  }

  // Last thing before the profile goes: a retry of anything above still finds
  // the grant to revoke, and once the row is gone there is nothing left that
  // needs it. Apple treats an already-revoked token the same as a fresh one,
  // so a retry that gets this far twice is harmless.
  if (appleGrant case AppleGrant(:final refreshToken, :final clientId)) {
    await request.apple.revokeGrant(refreshToken: refreshToken, clientId: clientId);
  }

  // Deleting the profile cascades to workouts, templates, workout_images, etc.
  await request.profileService.deleteAccount(userId: userId);

  // Fan out to the firebase service for the FB Auth user delete. We do this
  // last so the local cleanup is durable even if FB is unreachable — SQS will
  // retry the firebase delete independently.
  await request.events.publish(
    queueUrl: request.config.firebaseEventsQueueUrl,
    message: {'type': 'account.delete', 'uid': userId},
  );
}
