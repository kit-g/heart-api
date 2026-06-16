import '../models/exercise_preference.dart';

abstract interface class ExercisePreferenceService {
  Future<ExercisePreference> saveUnitPreference(ExercisePreference preference, String userId);

  Future<void> deleteUnitPreference(String exerciseId, String userId);
}
