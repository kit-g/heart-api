import 'package:heart_models/heart_models.dart';

abstract interface class ExerciseService {
  Future<Map<String, dynamic>> getExercises(String userId, {String? locale, bool owned = false});

  Future<Map<String, dynamic>> createExercise({
    required String userId,
    required String name,
    required String category,
    required String target,
    String? instructions,
  });

  Future<Map<String, dynamic>> updateExercise({
    required String userId,
    required String exerciseId,
    String? category,
    String? target,
    String? instructions,
    bool? archived,
  });

  /// Persists processed media onto the global exercise (user_id IS NULL) named
  /// [name]. Both [asset] and [thumbnail] are `{link, width, height}` blobs
  /// rendered by the assets pipeline. Throws [NotFound] if no such global
  /// exercise exists (e.g. the library hasn't been synced yet).
  Future<void> setExerciseMedia({
    required String name,
    required Map<String, dynamic> asset,
    required Map<String, dynamic> thumbnail,
  });
}

abstract interface class ExerciseResponse implements Model {
  Map<String, dynamic> get exerciseLibrary;

  factory ExerciseResponse({required Map<String, dynamic> exerciseLibrary}) = _ExerciseResponse.new;
}

class _ExerciseResponse implements ExerciseResponse {
  @override
  final Map<String, dynamic> exerciseLibrary;

  const _ExerciseResponse({required this.exerciseLibrary});

  @override
  Map<String, dynamic> toMap() => exerciseLibrary;
}

class ExerciseModel implements Model {
  final Map<String, dynamic> _row;

  const ExerciseModel(this._row);

  @override
  Map<String, dynamic> toMap() => _row;
}
