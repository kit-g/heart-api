part of 'db.dart';

mixin _ExercisePreferences on _DatabaseBase implements ExercisePreferenceService {
  @override
  Future<ExercisePreference> saveUnitPreference(ExercisePreference preference, String userId) async {
    await _pool.execute(
      _saveUnitPreference.toSql(),
      parameters: {
        'userId': userId,
        'exerciseId': preference.exerciseId,
        'unitSystem': preference.unitSystem.name,
      },
    );
    return preference;
  }

  @override
  Future<void> deleteUnitPreference(String exerciseId, String userId) async {
    await _pool.execute(
      _deleteUnitPreference.toSql(),
      parameters: {'id': exerciseId, 'userId': userId},
    );
  }
}
