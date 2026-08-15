import 'dart:convert';

import 'package:heart_models/heart_models.dart';

import 'errors.dart';
import 'imports.dart';

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
  /// (name/start/end/calories), leaving its exercises intact. A null argument
  /// leaves that field unchanged.
  Future<Workout> patchWorkout({
    required String userId,
    required String workoutId,
    required String Function(String) imageUrl,
    String? name,
    DateTime? start,
    DateTime? end,
    double? calories,
  });

  Future<void> deleteWorkout({
    required String userId,
    required String workoutId,
  });

  /// Bulk-writes a parsed CSV export in one shot: resolves or creates the
  /// exercises it references, then inserts the workouts that aren't already
  /// imported (matched on their deterministic import id, so re-runs are
  /// no-ops).
  Future<WorkoutImportReport> importWorkouts({
    required String userId,
    required WorkoutImport batch,
  });
}

class WorkoutRequest {
  final String userId;
  final Map<String, dynamic> body;

  const new({
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
              'met': ?ex['met'],
              'note': ?_note(ex['note']),
              'sets': ex['sets'] ?? [],
            };
          },
        )
        .where((e) => e['exercise_name'] != null)
        .toList();
  }

  /// Normalises a per-exercise note: trims, treats blank as absent (a cleared pin
  /// is no pin), and caps the length so it stays a pin, not an essay — comments
  /// are the place for prose. Over-long is a clean 400, not a raw DB CHECK error.
  static String? _note(Object? value) {
    if (value == null) return null;
    if (value is! String) throw const BadRequest(reason: 'an exercise note must be a string');
    final trimmed = value.trim();
    if (trimmed.isEmpty) return null;
    if (trimmed.length > _maxNoteLength) {
      throw const BadRequest(
        code: 'workout_note_too_long',
        reason: 'an exercise note is at most $_maxNoteLength characters',
      );
    }
    return trimmed;
  }

  static const _maxNoteLength = 500;

  Map<String, dynamic> toParams() {
    return {
      'userId': userId,
      'name': body['name'],
      'startedAt': _dt(body['start']),
      'completedAt': _dt(body['end']),
      'calories': (body['calories'] as num?)?.toDouble(),
      'exercises': jsonEncode(_exercises()),
    };
  }
}
