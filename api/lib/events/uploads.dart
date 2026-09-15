import 'package:heart/globals/config.dart';
import 'package:heart/middleware/database.dart';
import 'package:heart/middleware/s3.dart';
import 'package:heart/storage/keys.dart';
import 'package:heart_aws/heart_aws.dart';
import 'package:logging/logging.dart' as logging;
import 'package:relic/relic.dart';

final _logger = logging.Logger('uploads');

Future<void> imageUpload(
  Request request,
  String bucket,
  String uploadKey, {
  required Future<void> Function(Object error, [StackTrace? st]) onError,
}) async {
  Future<void> copyImage(String destinationKey) async {
    await request.imageStorageService.copyObject(fromKey: uploadKey, toKey: destinationKey);
    await request.imageStorageService.deleteObject(key: uploadKey);
  }

  /// Runs [record] after the object has been copied, and undoes the copy if it
  /// fails.
  ///
  /// The row is what makes the object reachable — the client only ever learns
  /// the key through it. A copy whose row never lands is unreferenced, sits
  /// under a prefix with no lifecycle rule, and cannot be found again, because
  /// the destination key carries a per-upload uuid. The copy also already
  /// deleted the source, so there is nothing to retry from.
  ///
  /// Reporting through [onError] matters as much as the cleanup: the SQS
  /// message is gone either way (the event source mapping deletes it when the
  /// invocation returns, whatever HTTP status the handler produced), so without
  /// the DLQ write a permanent failure leaves no trace at all.
  Future<void> recordOrUndo(String destinationKey, Future<void> Function() record) async {
    try {
      await record();
    } catch (e, st) {
      await request.imageStorageService.deleteObject(key: destinationKey);
      _logger.severe('recording $destinationKey failed; the copy was removed', e, st);
      await onError(e, st);
      rethrow;
    }
  }

  final tags = await request.imageStorageService.getObjectTagging(bucket, uploadKey);

  try {
    switch (tags) {
      // workout image
      case {
            'user-id': String userId,
            'workout-id': String workoutId,
            'image-id': String imageId,
          }
          when [userId, workoutId, imageId].every((attr) => attr.isNotEmpty):
        final ext = uploadKey.contains('.') ? uploadKey.split('.').last : 'jpg';
        final destKey = workoutImageKey(userId: userId, workoutId: workoutId, imageId: imageId, ext: ext);
        await copyImage(destKey);
        await recordOrUndo(
          destKey,
          () => request.imageDbService.recordImage(
            userId: userId,
            workoutId: workoutId,
            key: destKey,
            imageUrl: request.config.cdnAssetUrl,
          ),
        );

      // avatar
      case {
            'kind': 'avatar',
            'user-id': String userId,
          }
          when userId.isNotEmpty:
        final destKey = 'avatars/$userId';
        await copyImage(destKey);
        // No undo here, deliberately: the key is derived from the user id
        // alone, so a row that fails to update leaves one object the next
        // upload overwrites — not a new orphan per attempt.
        await request.profileService.updateAvatarUrl(
          userId: userId,
          avatarUrl: request.config.cdnAssetUrl(destKey),
        );

      // Neither shape: the upload carried tags this handler does not know, so
      // nothing was copied and nothing recorded. Silence here is how an upload
      // that lands in `uploads/` and is expired a day later by lifecycle looks
      // exactly like one that worked.
      default:
        _logger.warning('upload $uploadKey in $bucket matched no handler; tags: $tags');
    }
  } on AWSHttpException catch (e, st) {
    await onError(e, st);
  }
}
