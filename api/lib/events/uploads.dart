import 'package:heart/globals/config.dart';
import 'package:heart/middleware/database.dart';
import 'package:heart/middleware/s3.dart';
import 'package:heart/storage/keys.dart';
import 'package:heart_aws/heart_aws.dart';
import 'package:relic/relic.dart';

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
        await request.imageDbService.recordImage(
          userId: userId,
          workoutId: workoutId,
          key: destKey,
          imageUrl: request.config.cdnAssetUrl,
        );

      // avatar
      case {
            'kind': 'avatar',
            'user-id': String userId,
          }
          when userId.isNotEmpty:
        final destKey = 'avatars/$userId';
        await copyImage(destKey);
        await request.profileService.updateAvatarUrl(
          userId: userId,
          avatarUrl: request.config.cdnAssetUrl(destKey),
        );
    }
  } on AWSHttpException catch (e, st) {
    await onError(e, st);
  }
}
