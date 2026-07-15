import '../models/exercise_preference.dart';

abstract interface class ExercisePreferenceService {
  Future<ExercisePreference> savePreference(ExercisePreference preference, String userId);

  /// Clears a single pref [field] for `(user, exercise)`, leaving the other fields intact.
  Future<void> clearPreference(String exerciseId, String userId, ExercisePreferenceField field);
}
