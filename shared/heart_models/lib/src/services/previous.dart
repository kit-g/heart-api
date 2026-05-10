import '../models/exercise.dart';

abstract interface class PreviousExerciseService {
  Future<Map<ExerciseId, List<Map<String, dynamic>>>> getPreviousSets(String userId);
}
