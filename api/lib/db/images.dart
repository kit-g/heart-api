part of 'db.dart';

mixin _Images on _DatabaseBase implements ApiImageDbService {
  @override
  Future<GalleryResponse> getGallery({
    required String userId,
    required String Function(String) imageUrl,
    String? cursor,
    int? pageSize = 20,
  }) async {
    final rows = await _pool.execute(
      _listGallery.toSql(),
      parameters: {'userId': userId, 'cursor': cursor, 'limit': pageSize},
    );
    if (rows.isEmpty) return const GalleryResponse(images: []);
    final images = rows.map(
      (row) {
        final m = row.toColumnMap();
        final key = m['key'] as String;
        return WorkoutImage.fromRow(imageUrl(key), m);
      },
    ).toList();
    return GalleryResponse(
      images: images,
      cursor: rows.last.toColumnMap()['id']?.toString(),
    );
  }

  @override
  Future<WorkoutImage> recordImage({
    required String userId,
    required String workoutId,
    required String key,
    required String Function(String) imageUrl,
  }) async {
    final rows = await _pool.execute(
      _insertImage.toSql(),
      parameters: {'userId': userId, 'workoutId': workoutId, 'key': key},
    );
    final m = rows.first.toColumnMap();
    final rowKey = m['key'] as String;
    return WorkoutImage.fromRow(imageUrl(rowKey), rows.first.toColumnMap());
  }

  @override
  Future<List<String>> getUserImageKeys({required String userId}) async {
    final rows = await _pool.execute(
      _getUserImageKeys.toSql(),
      parameters: {'userId': userId},
    );
    return rows.map((r) => r.toColumnMap()['key'] as String).toList();
  }

  @override
  Future<List<String>> getWorkoutImageKeys({required String userId, required String workoutId}) async {
    final rows = await _pool.execute(
      _getWorkoutImageKeys.toSql(),
      parameters: {'userId': userId, 'workoutId': workoutId},
    );
    return rows.map((r) => r.toColumnMap()['key'] as String).toList();
  }

  @override
  Future<void> deleteImageRecord({
    required String userId,
    required String workoutId,
    required String key,
  }) async {
    final rows = await _pool.execute(
      _deleteImage.toSql(),
      parameters: {'userId': userId, 'workoutId': workoutId, 'key': key},
    );
    if (rows.isEmpty) throw NotFound(type: 'WorkoutImage', id: key);
  }
}
