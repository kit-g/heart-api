import 'dart:convert';

import 'package:heart_models/heart_models.dart';

abstract interface class ApiWorkoutService {
  Future<Page<Workout>> getWorkouts({
    required String userId,
    required String targetUserId,
    required String Function(String) imageUrl,
    String? cursor,
    int limit,
  });

  Future<Workout> getWorkout({
    required String userId,
    required String workoutId,
    required String Function(String) imageUrl,
  });

  Future<Workout> getTargetWorkout({
    required String requesterId,
    required String targetUserId,
    required String workoutId,
    required String Function(String) imageUrl,
  });

  Future<Workout> createWorkout({
    required String userId,
    required WorkoutRequest body,
    required String Function(String) imageUrl,
  });

  Future<Workout> updateWorkout({
    required String userId,
    required String workoutId,
    required WorkoutRequest body,
    required String Function(String) imageUrl,
  });

  /// Partial update of a workout the user owns — sets only the provided fields
  /// (name/start/end), leaving its exercises intact. A null argument leaves that
  /// field unchanged.
  Future<Workout> patchWorkout({
    required String userId,
    required String workoutId,
    required String Function(String) imageUrl,
    String? name,
    DateTime? start,
    DateTime? end,
  });

  Future<void> deleteWorkout({
    required String userId,
    required String workoutId,
  });
}

class WorkoutRequest {
  final String userId;
  final Map<String, dynamic> body;

  const WorkoutRequest({
    required this.userId,
    required this.body,
  });

  DateTime? _dt(dynamic value) => switch (value) {
    String s => DateTime.tryParse(s),
    DateTime dt => dt,
    _ => null,
  };

  List<Map> _exercises() {
    return ((body['exercises'] as List? ?? []).cast<Map>())
        .map(
          (ex) {
            final name = switch (ex['exercise']) {
              String s => s,
              {'name': String n} => n,
              _ => null,
            };
            return {
              'exercise_name': name,
              'order': ex['order'],
              'sets': ex['sets'] ?? [],
            };
          },
        )
        .where((e) => e['exercise_name'] != null)
        .toList();
  }

  Map<String, dynamic> toParams() {
    return {
      'userId': userId,
      'name': body['name'],
      'startedAt': _dt(body['start']),
      'completedAt': _dt(body['end']),
      'exercises': jsonEncode(_exercises()),
    };
  }
}
