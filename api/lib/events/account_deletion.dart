import 'package:heart/globals/config.dart';
import 'package:heart/middleware/database.dart';
import 'package:heart/middleware/events.dart';
import 'package:heart/middleware/s3.dart';
import 'package:relic/relic.dart';

Future<void> accountDeletion(Request request, String userId) async {
  // Delete workout images from S3 before the DB cascade removes the records.
  // S3 DELETE is idempotent so retries are safe.
  final keys = await request.imageDbService.getUserImageKeys(userId: userId);
  for (final key in keys) {
    await request.imageStorageService.deleteObject(key: key);
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
