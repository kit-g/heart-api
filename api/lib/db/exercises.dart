part of 'db.dart';

mixin _Exercises on _DatabaseBase implements ExerciseService {
  @override
  Future<Map<String, dynamic>> getExercises(String userId, {String? locale, bool owned = false}) async {
    final rows = await _pool.execute(
      _listExercises.toSql(),
      parameters: {'userId': userId, 'locale': locale, 'owned': owned},
    );
    return {'exercises': rows.first.toColumnMap()['exercises'] as List? ?? const []};
  }

  @override
  Future<Map<String, dynamic>> createExercise({
    required String userId,
    required String name,
    required String category,
    required String target,
    String? instructions,
  }) async {
    final rows = await _pool.execute(
      _createExercise.toSql(),
      parameters: {
        'userId': userId,
        'name': name,
        'category': category,
        'target': target,
        'instructions': instructions,
      },
    );
    return rows.first.toColumnMap();
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
}
