part of 'db.dart';

mixin _ExercisePreferences on _DatabaseBase implements ApiExercisePreferenceService {
  @override
  Future<Iterable<ExercisePreference>> getExercisePreferences(String userId) async {
    final result = await _pool.execute(
      _listExercisePreferences.toSql(),
      parameters: {'userId': userId},
    );
    return result.map(
      (row) {
        final map = row.toColumnMap();
        return ExercisePreference(
          exerciseId: map['exercise_id'].toString(),
          unitSystem: switch (map['unit_system']) {
            null => null,
            final String u => MeasurementUnit.fromString(u),
            final other => throw ArgumentError.value(other, 'unit_system', 'unexpected exercise_preferences value'),
          },
          restTimer: map['rest_timer'] as int?,
        );
      },
    );
  }

  @override
  Future<ExercisePreference> savePreference(ExercisePreference preference, String userId) async {
    await _pool.execute(
      _saveExercisePreference.toSql(),
      parameters: {
        'userId': userId,
        'exerciseId': preference.exerciseId,
        'unitSystem': preference.unitSystem?.name,
        'restTimer': preference.restTimer,
      },
    );
    return preference;
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
