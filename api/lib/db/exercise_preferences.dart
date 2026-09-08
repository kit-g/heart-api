part of 'db.dart';

mixin _ExercisePreferences on _DatabaseBase implements ApiExercisePreferenceService {
  @override
  Future<Iterable<ExercisePreference>> getExercisePreferences(String userId) async {
    final result = await _pool.execute(
      _listExercisePreferences.toSql(),
      parameters: {'userId': userId},
    );
    return result.map((row) => _preferenceOf(row.toColumnMap()));
  }

  ExercisePreference _preferenceOf(Map<String, dynamic> row) {
    return ExercisePreference(
      exerciseId: row['exercise_id'].toString(),
      unitSystem: switch (row['unit_system']) {
        null => null,
        final String u => MeasurementUnit.fromString(u),
        final other => throw ArgumentError.value(other, 'unit_system', 'unexpected exercise_preferences value'),
      },
      restTimer: row['rest_timer'] as int?,
    );
  }

  @override
  Future<ExercisePreference> savePreference(ExercisePreference preference, String userId) async {
    final rows = await _pool.execute(
      _saveExercisePreference.toSql(),
      parameters: {
        'userId': userId,
        'exerciseId': preference.exerciseId,
        'unitSystem': preference.unitSystem?.name,
        'restTimer': preference.restTimer,
      },
    );
    // No row means the id matched no exercise this caller may reference — it
    // does not exist, or it is someone else's private custom. One answer for
    // both; see `_saveExercisePreference`.
    if (rows.isEmpty) {
      throw NotFound(type: 'Exercise', id: preference.exerciseId, code: 'unknown_exercise');
    }
    return _preferenceOf(rows.first.toColumnMap());
  }

  @override
  Future<void> clearPreference(String exerciseId, String userId, ExercisePreferenceField field) async {
    final query = switch (field) {
      .unitSystem => _clearUnitPreference,
      .restTimer => _clearRestTimer,
    };
    await _pool.execute(
      query.toSql(),
      parameters: {'id': exerciseId, 'userId': userId},
    );
  }
}
