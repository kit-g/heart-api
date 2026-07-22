import '../models/exercise_set.dart';
import '../models/misc.dart';
import '../models/workout.dart';

abstract interface class GalleryService {
  Future<ProgressGalleryResponse> getWorkoutGallery({String? cursor, String? userId});
}

abstract interface class WorkoutService implements GalleryService {
  Future<void> startWorkout(Workout workout, String userId);

  Future<void> deleteWorkout(String workoutId);

  Future<void> finishWorkout(Workout workout, String userId);

  Future<void> startExercise(String workoutId, WorkoutExercise exercise);

  Future<void> removeExercise(WorkoutExercise exercise);

  Future<void> addSet(WorkoutExercise exercise, ExerciseSet set);

  Future<void> removeSet(ExerciseSet set);

  Future<void> storeMeasurements(ExerciseSet set);

  Future<void> markSetAsComplete(ExerciseSet set);

  Future<void> markSetAsIncomplete(ExerciseSet set);

  Future<Workout?> getActiveWorkout(String? userId);

  Future<Workout?> getWorkout(String? userId, String workoutId);

  Future<void> storeWorkoutHistory(Iterable<Workout> history, String userId);

  Future<Iterable<Workout>?> getWorkoutHistory(String userId);

  Future<void> updateWorkout({required String workoutId, String? name, Iterable<WorkoutImage>? images});

  /// Persists the display order of a workout's exercises. [orderedIds] are
  /// [WorkoutExercise.id]s in the order they should be read back.
  ///
  /// The active workout is only pushed to the server once it's finished, so a
  /// reorder mid-workout has nowhere else to live — without this it survives
  /// only in memory.
  Future<void> saveExerciseOrder(Iterable<String> orderedIds, String workoutId);
}

abstract interface class RemoteWorkoutService implements FileUploadService, GalleryService {
  Future<Iterable<Workout>?> getWorkouts(
    String userId, {
    int? pageSize,
    String? since,
  });

  Future<Workout> saveWorkout(Workout workout);

  Future<Workout> editWorkout(Workout updated);

  Future<bool> deleteWorkout(String workoutId);

  Future<(({String url, Map<String, String> fields})?, String?)> getWorkoutUploadLink(
    String workoutId, {
    String? imageMimeType,
  });

  Future<bool> deleteWorkoutImage(String workoutId, String imageId);
}
