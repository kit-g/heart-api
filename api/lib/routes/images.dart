import 'dart:convert';

import 'package:heart/core/request.dart';
import 'package:heart/globals/config.dart';
import 'package:heart/globals/globals.dart';
import 'package:heart/inputs/inputs.dart';
import 'package:heart/middleware/database.dart';
import 'package:heart/middleware/s3.dart';
import 'package:heart/models/errors.dart';
import 'package:heart/models/images.dart';
import 'package:heart/models/pagination.dart';
import 'package:heart_aws/heart_aws.dart';
import 'package:heart_models/heart_models.dart';
import 'package:mime/mime.dart';
import 'package:relic/relic.dart';

const _defaultMimeType = 'image/jpeg';

(String, String) _imageKey({
  required String userId,
  required String workoutId,
  required String imageId,
  required String mimeType,
}) {
  final hash = sha256.convert(utf8.encode('$userId:$workoutId')).toString().substring(0, 16);
  final ext = extensionFromMime(mimeType) ?? 'jpg';
  return ('workouts/$hash/$imageId.$ext', ext);
}

Future<Paginated<WorkoutImage>> getGallery(final Request request) async {
  final query = PageQuery.fromRequest(request, defaultLimit: 20);
  final page = await request.imageDbService.getGallery(
    userId: request.userId,
    imageUrl: request.config.cdnAssetUrl,
    limit: query.limit,
    cursor: query.cursor,
  );
  return Paginated<WorkoutImage>.from(page, itemsKey: 'images', cursorOf: (i) => i.id);
}

Future<PresignedUploadResponse> presignWorkoutImage(final Request request) async {
  final workoutId = request.pathParameters.raw[#workoutId]!;
  final body = await request.json();
  final mimeType = (body['mimeType'] as String?) ?? _defaultMimeType;

  if (!request.config.allowedMimeTypes.contains(mimeType)) {
    throw BadRequest(
      reason: 'Unsupported image type: $mimeType. Allowed types: ${request.config.allowedMimeTypes.join(', ')}',
    );
  }

  final imageId = uuidV7();
  final (key, ext) = _imageKey(userId: request.userId, workoutId: workoutId, mimeType: mimeType, imageId: imageId);
  final uploadKey = 'uploads/$imageId.$ext';

  final presignedUrl = await request.imageStorageService.presignUpload(
    key: uploadKey,
    mimeType: mimeType,
    tags: [
      ('destination', request.config.contentBucket),
      ('user-id', request.userId),
      ('workout-id', workoutId),
      ('image-id', imageId),
      ('kind', 'workout-image'),
    ],
  );

  return PresignedUploadResponse(
    preSignedUrl: presignedUrl,
    destinationUrl: request.config.cdnAssetUrl(key),
    key: key,
  );
}

Future<NoContent> deleteWorkoutImage(final Request request) async {
  final workoutId = request.pathParameters.raw[#workoutId]!;
  final key = request.queryParameters.raw['key'];
  if (key == null || key.isEmpty) {
    throw const BadRequest(reason: 'Missing query param: key');
  }

  await request.imageStorageService.deleteObject(key: key);
  await request.imageDbService.deleteImageRecord(
    userId: request.userId,
    workoutId: workoutId,
    key: key,
  );

  throw const NoContent();
}
