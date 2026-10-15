import 'package:heart_models/heart_models.dart';

abstract interface class ExerciseService {
  Future<Map<String, dynamic>> getExercises(String userId, {String? locale, bool owned = false});

  Future<Map<String, dynamic>> createExercise({
    required String userId,
    String? id,
    required String name,
    required String category,
    required String target,
    String? instructions,
    String? pattern,
  });

  /// [pattern] null leaves the movement pattern alone; `(value: null)` clears
  /// it.
  Future<Map<String, dynamic>> updateExercise({
    required String userId,
    required String exerciseId,
    String? category,
    String? target,
    String? instructions,
    bool? archived,
    ({String? value})? pattern,
  });

  /// Persists processed media onto the global exercise (user_id IS NULL) named
  /// [name]. Both [asset] and [thumbnail] are `{link, width, height}` blobs
  /// rendered by the assets pipeline. Throws [NotFound] if no such global
  /// exercise exists (e.g. the library hasn't been synced yet).
  Future<void> setExerciseMedia({
    required String key,
    required Map<String, dynamic> asset,
    required Map<String, dynamic> thumbnail,
  });

  /// Re-keys everything [userId] has under [sourceId] (logged workouts,
  /// routines, per-exercise preferences, goals) onto [targetId], in one
  /// transaction, and deletes the source when it is the user's own custom.
  /// With [dryRun], reports the same counts and writes nothing. Throws
  /// [NotFound] (`unknown_exercise`) for an id the user cannot reference —
  /// missing or someone else's custom, told apart by nothing.
  Future<ExerciseMoveReport> moveExerciseHistory({
    required String userId,
    required String sourceId,
    required String targetId,
    required bool dryRun,
  });
}

abstract interface class ExerciseResponse implements Model {
  Map<String, dynamic> get exerciseLibrary;

  factory({required Map<String, dynamic> exerciseLibrary}) = _ExerciseResponse.new;
}

class _ExerciseResponse implements ExerciseResponse {
  @override
  final Map<String, dynamic> exerciseLibrary;

  const new({required this.exerciseLibrary});

  @override
  Map<String, dynamic> toMap() => exerciseLibrary;
}

class ExerciseModel implements Model {
  final Map<String, dynamic> _row;

  const new(this._row);

  @override
  Map<String, dynamic> toMap() => _row;
}
