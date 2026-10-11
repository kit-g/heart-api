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

/// What a move did — or, for a dry run, would do: how many rows of each kind
/// now point at the target, and whether the source is gone.
class ExerciseMoveReport implements Model {
  final String sourceId;
  final String targetId;
  final bool dryRun;
  final int workoutExercises;
  final int templateExercises;

  /// Preference rows re-keyed. A preference the user had on both sides is not
  /// among them: the target's row is kept and the source's dropped.
  final int preferences;

  /// Preference rows dropped because the target already had one: 0 or 1, and
  /// the one thing a move loses, so a preview says it.
  final int preferencesDropped;

  /// Of [preferences], the ones carrying a chart setting.
  final int chartPreferences;
  final int goals;

  /// Whether the source was (or, dry, would be) deleted: true for the user's
  /// own custom, never for a library exercise.
  final bool sourceDeleted;

  const new({
    required this.sourceId,
    required this.targetId,
    required this.dryRun,
    required this.workoutExercises,
    required this.templateExercises,
    required this.preferences,
    required this.preferencesDropped,
    required this.chartPreferences,
    required this.goals,
    required this.sourceDeleted,
  });

  factory fromRow(
    Map<String, dynamic> row, {
    required String sourceId,
    required String targetId,
    required bool dryRun,
  }) {
    return ExerciseMoveReport(
      sourceId: sourceId,
      targetId: targetId,
      dryRun: dryRun,
      workoutExercises: row['workout_exercises_moved'],
      templateExercises: row['template_exercises_moved'],
      preferences: row['preferences_moved'],
      preferencesDropped: row['preferences_dropped'],
      chartPreferences: row['chart_preferences_moved'],
      goals: row['goals_moved'],
      sourceDeleted: row['source_deleted'],
    );
  }

  @override
  Map<String, dynamic> toMap() {
    return {
      'sourceId': sourceId,
      'targetId': targetId,
      'dryRun': dryRun,
      'workoutExercises': workoutExercises,
      'templateExercises': templateExercises,
      'preferences': preferences,
      'preferencesDropped': preferencesDropped,
      'chartPreferences': chartPreferences,
      'goals': goals,
      'sourceDeleted': sourceDeleted,
    };
  }
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
