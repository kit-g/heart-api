import 'package:heart_models/heart_models.dart';
import 'package:test/test.dart';

void main() {
  const source = '019def00-0000-7000-8000-000000000001';
  const target = '019def00-0000-7000-8000-000000000002';

  test('round-trips through toMap and fromJson', () {
    final report = ExerciseMoveReport(
      sourceId: source,
      targetId: target,
      dryRun: false,
      workoutExercises: 12,
      templateExercises: 2,
      preferences: 1,
      preferencesDropped: 0,
      chartPreferences: 0,
      goals: 1,
      programs: 2,
      sourceDeleted: true,
    );

    final map = report.toMap();
    expect(map, {
      'sourceId': source,
      'targetId': target,
      'dryRun': false,
      'workoutExercises': 12,
      'templateExercises': 2,
      'preferences': 1,
      'preferencesDropped': 0,
      'chartPreferences': 0,
      'goals': 1,
      'programs': 2,
      'sourceDeleted': true,
    });

    final back = ExerciseMoveReport.fromJson(map);
    expect(back.toMap(), map);
    expect(back.sourceDeleted, isTrue);
    expect(back.preferencesDropped, 0);
  });

  test('reads the function row, with the ids and the mode from the call', () {
    final report = ExerciseMoveReport.fromRow(
      {
        'workout_exercises_moved': 3,
        'template_exercises_moved': 0,
        'preferences_moved': 0,
        'preferences_dropped': 1,
        'chart_preferences_moved': 0,
        'goals_moved': 2,
        'programs_moved': 1,
        'source_deleted': false,
      },
      sourceId: source,
      targetId: target,
      dryRun: true,
    );
    expect(report.dryRun, isTrue);
    expect(report.workoutExercises, 3);
    expect(report.preferencesDropped, 1);
    expect(report.goals, 2);
    expect(report.programs, 1);
    expect(report.sourceDeleted, isFalse);
  });

  test('a server that predates programs reads as none moved', () {
    final report = ExerciseMoveReport.fromJson({
      'sourceId': source,
      'targetId': target,
      'dryRun': true,
      'workoutExercises': 0,
      'templateExercises': 0,
      'preferences': 0,
      'preferencesDropped': 0,
      'chartPreferences': 0,
      'goals': 0,
      'sourceDeleted': false,
    });
    expect(report.programs, 0);
  });

  test('fromJson rejects a missing count', () {
    expect(
      () => ExerciseMoveReport.fromJson({'sourceId': source, 'targetId': target, 'dryRun': false}),
      throwsA(isA<TypeError>()),
    );
  });
}
