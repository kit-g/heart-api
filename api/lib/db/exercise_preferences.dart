part of 'db.dart';

mixin _ExercisePreferences on _DatabaseBase implements ExercisePreferenceService {
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
