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
  ///
  /// [createCustom] is the user's consent decision from the preview: the
  /// unmatched names to create as their custom exercises. Null means create
  /// all (the legacy, no-preview flow); declined names have their sets
  /// skipped and counted in the report.
  Future<WorkoutImportReport> importWorkouts({
    required String userId,
    required WorkoutImport batch,
    List<String>? createCustom,
  });

  /// The read-only half of a two-phase import: what [importWorkouts] would
  /// do with [batch] — how many workouts are new vs already imported, and
  /// which exercise names would need creating — without writing anything.
  Future<WorkoutImportPreview> previewImport({
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
    final source = (body['exercises'] as List? ?? []).cast<Map>();
    final out = <Map>[];
    for (final (index, ex) in source.indexed) {
      // an emptied editor row names nothing and means "no exercise here",
      // matching the pre-cutover silent drop of nameless rows
      if (ex['exercise'] == null) continue;
      out.add({
        // The reference is the exercise's uuid — the name is localized
        // display copy and resolves nothing since the id cutover. A present
        // but malformed reference is the client's mistake: a 400, not a
        // silent drop.
        'exercise_id': switch (ex['exercise']) {
          final String id when isUuidV7(id) => id,
          {'id': final String id} when isUuidV7(id) => id,
          _ => throw BadRequest(reason: 'exercises[$index].exercise must reference an exercise by its id'),
        },
        // A v7 id round-trips so a save keeps the row's identity — the
        // clients read an act's start off the id's mint instant, and a
        // re-minted id silently moves every act to "edited just now".
        // Anything else (absent, Firebase-era, garbage) is dropped and
        // the insert mints from 'start' instead.
        'id': ?_v7OrNull(ex['id']),
        'start': ?_dt(ex['start'])?.toIso8601String(),
        'order': ex['order'],
        'met': ?ex['met'],
        'note': ?_note(ex['note']),
        'sets': [
          for (final set in (ex['sets'] as List? ?? []).cast<Map>()) _set(set),
        ],
      });
    }
    return out;
  }

  /// The same id round-trip for a set: keep a v7, strip anything else so the
  /// insert can cast-or-mint without tripping on a legacy id.
  static Map _set(Map set) {
    final copy = {...set}..remove('id');
    if (_v7OrNull(set['id']) case String id) {
      copy['id'] = id;
    }
    return copy;
  }

  static String? _v7OrNull(Object? value) {
    return switch (value) {
      String id when isUuidV7(id) => id,
      _ => null,
    };
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
