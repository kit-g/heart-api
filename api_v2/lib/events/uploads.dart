import 'dart:convert';

import 'package:aws_common/aws_common.dart';
import 'package:crypto/crypto.dart';
import 'package:heart/globals/config.dart';
import 'package:heart/middleware/database.dart';
import 'package:heart/middleware/s3.dart';
import 'package:relic/relic.dart';

Future<void> imageUpload(
  final Request request,
  String bucket,
  String uploadKey, {
  required void Function(Object error, [StackTrace? st]) onError,
}) async {
  try {
    final tags = await request.imageStorageService.getObjectTagging(bucket, uploadKey);

    final userId = tags['user-id'];
    final workoutId = tags['workout-id'];
    final imageId = tags['image-id'];

    if (userId == null || workoutId == null || imageId == null) return;

    final ext = uploadKey.contains('.') ? uploadKey.split('.').last : 'jpg';
    final hash = sha256.convert(utf8.encode('$userId:$workoutId')).toString().substring(0, 16);
    final destKey = 'workouts/$hash/$imageId.$ext';

    await request.imageStorageService.copyObject(fromKey: uploadKey, toKey: destKey);
    await request.imageStorageService.deleteObject(key: uploadKey);
    await request.imageDbService.recordImage(
      userId: userId,
      workoutId: workoutId,
      key: destKey,
      imageUrl: request.config.workoutImageUrl,
    );
  } on AWSHttpException catch (e, st) {
    onError(e, st);
  }
}
