import 'package:heart_models/heart_models.dart';

abstract interface class ApiImageStorageService {
  Future<PreSignedUrl> presignUpload({
    required String key,
    required String mimeType,
    List<(String, String)>? tags,
  });

  Future<void> deleteObject({required String key});
}

abstract interface class ApiImageDbService {
  Future<GalleryResponse> getGallery({
    required String userId,
    required String Function(String) imageUrl,
    String? cursor,
    int? pageSize,
  });

  Future<WorkoutImage> recordImage({
    required String userId,
    required String workoutId,
    required String key,
    required String Function(String) imageUrl,
  });

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

class GalleryResponse with Iterable<WorkoutImage> implements Model {
  final List<WorkoutImage> images;
  final String? cursor;

  const GalleryResponse({required this.images, this.cursor});

  @override
  Iterator<WorkoutImage> get iterator => images.iterator;

  @override
  Map<String, dynamic> toMap() => {
    'images': map((img) => img.toRow()).toList(),
    'cursor': ?cursor,
  };
}
