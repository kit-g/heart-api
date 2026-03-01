import 'package:heart_models/heart_models.dart';

abstract interface class ExerciseService {
  Future<Map<String, dynamic>> getExercises(String userId, {String? locale});
}

abstract interface class ExerciseResponse implements Model {
  Map<String, dynamic> get exerciseLibrary;

  factory ExerciseResponse({required final Map<String, dynamic> exerciseLibrary}) = _ExerciseResponse.new;
}

class _ExerciseResponse implements ExerciseResponse {
  @override
  final Map<String, dynamic> exerciseLibrary;

  const _ExerciseResponse({required this.exerciseLibrary});

  @override
  Map<String, dynamic> toMap() => exerciseLibrary;
}
