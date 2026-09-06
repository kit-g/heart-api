part of 'db.dart';

mixin _Exercises on _DatabaseBase implements ExerciseService {
  @override
  Future<Map<String, dynamic>> getExercises(String userId, {String? locale, bool owned = false}) async {
    final rows = await _pool.execute(
      _listExercises.toSql(),
      parameters: {
        'userId': userId,
        'locale': locale,
        // regional locales (es_ES) fall back to their base language (es)
        // before the master columns; see the tb join in _listExercises
        'baseLocale': locale?.split('_').first,
        'owned': owned,
      },
    );
    return {'exercises': rows.first.toColumnMap()['exercises'] as List? ?? const []};
  }

  @override
  Future<Map<String, dynamic>> createExercise({
    required String userId,
    String? id,
    required String name,
    required String category,
    required String target,
    String? instructions,
  }) async {
    try {
      final rows = await _retryOnCreateRace(
        () => _pool.execute(
          _createExercise.toSql(),
          parameters: {
            'userId': userId,
            'id': id,
            'name': name,
            'category': category,
            'target': target,
            'instructions': instructions,
          },
        ),
      );
      // Empty means the pre-check missed (the id belongs to someone else) and
      // the insert itself was never attempted at all — impossible with the
      // current statement, but the exception path below is what actually
      // handles that case; this is just the type-safe fallback.
      if (rows.isEmpty) throw _idTaken;
      // `created` rides along in the row map — routes/exercises.dart strips it
      // before serializing and uses it to pick 200 vs 201.
      return rows.first.toColumnMap();
    } on ServerException catch (e) {
      _rethrowForeignId(e);
    }
  }

  @override
  Future<Map<String, dynamic>> updateExercise({
    required String userId,
    required String exerciseId,
    String? category,
    String? target,
    String? instructions,
    bool? archived,
  }) async {
    final rows = await _pool.execute(
      _updateExercise.toSql(),
      parameters: {
        'userId': userId,
        'exerciseId': exerciseId,
        'category': category,
        'target': target,
        'instructions': instructions,
        'archived': archived,
      },
    );
    if (rows.isEmpty) throw NotFound(type: 'Exercise', id: exerciseId);
    return rows.first.toColumnMap();
  }

  @override
  Future<void> setExerciseMedia({
    required String key,
    required Map<String, dynamic> asset,
    required Map<String, dynamic> thumbnail,
  }) async {
    final rows = await _pool.execute(
      _setExerciseMedia.toSql(),
      parameters: {
        'key': key,
        'asset': jsonEncode(asset),
        'thumbnail': jsonEncode(thumbnail),
      },
    );
    if (rows.isEmpty) throw NotFound(type: 'Exercise', id: key);
  }
}
