import 'package:heart/globals/config.dart';
import 'package:heart/globals/globals.dart';
import 'package:heart/inputs/inputs.dart';
import 'package:heart/middleware/database.dart';
import 'package:heart/middleware/s3.dart';
import 'package:heart/models/errors.dart';
import 'package:heart/models/images.dart';
import 'package:heart/models/pagination.dart';
import 'package:heart/storage/keys.dart';
import 'package:heart_models/heart_models.dart';
import 'package:relic/relic.dart';

Future<Paginated<WorkoutImage>> getGallery(Request request) async {
  final query = PageQuery.fromRequest(request, defaultLimit: 20);
  final page = await request.imageDbService.getGallery(
    userId: request.userId,
    imageUrl: request.config.cdnAssetUrl,
    limit: query.limit,
    cursor: query.cursor,
  );
  return Paginated<WorkoutImage>.from(page, itemsKey: 'images', cursorOf: (i) => i.id);
}

Future<PresignedUploadResponse> presignWorkoutImage(Request request) {
  return presignWorkoutImageById(request, request.pathParameters.raw[#workoutId]!);
}

Future<PresignedUploadResponse> presignWorkoutImageById(Request request, String workoutId) async {
  final input = await WorkoutImagePresignIn.fromRequest(request);

  // Refuse before the upload rather than after it. Without this the presign
  // succeeds for a workout the caller does not have, the client uploads
  // happily, and the failure only surfaces in the event handler when the
  // `workout_id` FK rejects the row — by which point the object has been
  // copied and its source deleted, leaving an object nothing references.
  //
  // `getWorkout` rather than a cheaper exists-query so ownership is decided in
  // one place (it 404s a workout belonging to someone else, same as reading
  // it); the cost is one read of the workout blob per presign.
  await request.workoutsService.getWorkout(
    userId: request.userId,
    workoutId: workoutId,
    imageUrl: request.config.cdnAssetUrl,
  );

  final imageId = uuidV7();
  final key = workoutImageKey(userId: request.userId, workoutId: workoutId, imageId: imageId, ext: input.ext);
  final uploadKey = 'uploads/$imageId.${input.ext}';

  final presignedUrl = await request.imageStorageService.presignUpload(
    key: uploadKey,
    mimeType: input.mimeType,
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

Future<NoContent> deleteWorkoutImage(Request request) async {
  final workoutId = request.pathParameters.raw[#workoutId]!;
  final query = WorkoutImageDeleteQuery.fromRequest(request);

  await request.imageStorageService.deleteObject(key: query.key);
  await request.imageDbService.deleteImageRecord(
    userId: request.userId,
    workoutId: workoutId,
    key: query.key,
  );

  throw const NoContent();
}
