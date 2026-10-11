import 'misc.dart';

/// What moving one exercise's history onto another did — or, for a dry run,
/// would do: how many rows of each kind now point at the target, and whether
/// the source is gone. The answer of `POST /exercises/:exerciseId/moves`.
abstract interface class ExerciseMoveReport implements Model {
  /// The exercise the history was moved away from.
  String get sourceId;

  /// The exercise it now belongs to.
  String get targetId;

  /// True when nothing was written and the counts say what a move would do.
  bool get dryRun;

  /// Logged exercises re-keyed, across the user's workouts.
  int get workoutExercises;

  /// Routine entries re-keyed, across the user's templates, shared ones included.
  int get templateExercises;

  /// Per-exercise preference rows re-keyed. A preference the user had on both
  /// sides is not among them: the target's row is kept and the source's dropped.
  int get preferences;

  /// Preference rows dropped because the target already had one: 0 or 1, and
  /// the one thing a move loses.
  int get preferencesDropped;

  /// Of [preferences], the ones carrying a chart setting.
  int get chartPreferences;

  /// Goals re-keyed.
  int get goals;

  /// Whether the source was (or, dry, would be) deleted: true for the user's
  /// own custom exercise, never for a library one.
  bool get sourceDeleted;

  factory({
    required String sourceId,
    required String targetId,
    required bool dryRun,
    required int workoutExercises,
    required int templateExercises,
    required int preferences,
    required int preferencesDropped,
    required int chartPreferences,
    required int goals,
    required bool sourceDeleted,
  }) = _ExerciseMoveReport;

  /// Wire/JSON shape — camelCase.
  factory fromJson(Map json) {
    return _ExerciseMoveReport(
      sourceId: json['sourceId'] as String,
      targetId: json['targetId'] as String,
      dryRun: json['dryRun'] as bool,
      workoutExercises: json['workoutExercises'] as int,
      templateExercises: json['templateExercises'] as int,
      preferences: json['preferences'] as int,
      preferencesDropped: json['preferencesDropped'] as int,
      chartPreferences: json['chartPreferences'] as int,
      goals: json['goals'] as int,
      sourceDeleted: json['sourceDeleted'] as bool,
    );
  }

  /// Database row shape — the one row `_move_exercise_history` returns,
  /// snake_case; the ids and the mode are the call's own.
  factory fromRow(
    Map<String, dynamic> row, {
    required String sourceId,
    required String targetId,
    required bool dryRun,
  }) {
    return _ExerciseMoveReport(
      sourceId: sourceId,
      targetId: targetId,
      dryRun: dryRun,
      workoutExercises: row['workout_exercises_moved'] as int,
      templateExercises: row['template_exercises_moved'] as int,
      preferences: row['preferences_moved'] as int,
      preferencesDropped: row['preferences_dropped'] as int,
      chartPreferences: row['chart_preferences_moved'] as int,
      goals: row['goals_moved'] as int,
      sourceDeleted: row['source_deleted'] as bool,
    );
  }
}

class _ExerciseMoveReport implements ExerciseMoveReport {
  @override
  final String sourceId;
  @override
  final String targetId;
  @override
  final bool dryRun;
  @override
  final int workoutExercises;
  @override
  final int templateExercises;
  @override
  final int preferences;
  @override
  final int preferencesDropped;
  @override
  final int chartPreferences;
  @override
  final int goals;
  @override
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
