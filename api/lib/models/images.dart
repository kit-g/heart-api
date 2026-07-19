import 'package:heart_models/heart_models.dart';

abstract interface class ApiImageStorageService {
  Future<PreSignedUrl> presignUpload({
    required String key,
    required String mimeType,
    List<(String, String)>? tags,
  });

  Future<Map<String, String>> getObjectTagging(String bucket, String key);

  Future<String> getObject(String bucket, String key);

  Future<void> copyObject({required String fromKey, required String toKey});

  Future<void> deleteObject({required String key});
}

abstract interface class ApiImageDbService {
  Future<Page<WorkoutImage>> getGallery({
    required String userId,
    required String Function(String) imageUrl,
    String? cursor,
    int limit,
  });

  Future<WorkoutImage> recordImage({
    required String userId,
    required String workoutId,
    required String key,
    required String Function(String) imageUrl,
  });

  Future<List<String>> getUserImageKeys({required String userId});

  Future<List<String>> getWorkoutImageKeys({required String userId, required String workoutId});

  Future<void> deleteImageRecord({
    required String userId,
    required String workoutId,
    required String key,
  });
}

class PresignedUploadResponse implements Model {
  final PreSignedUrl preSignedUrl;
  final String destinationUrl;
  final String key;

  const PresignedUploadResponse({
    required this.preSignedUrl,
    required this.destinationUrl,
    required this.key,
  });

  @override
  Map<String, dynamic> toMap() {
    return {
      'url': preSignedUrl.url,
      'destinationUrl': destinationUrl,
      'key': key,
      'fields': preSignedUrl.fields,
    };
  }
}
