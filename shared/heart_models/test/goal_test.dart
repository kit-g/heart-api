import 'package:heart_models/heart_models.dart';
import 'package:test/test.dart';

void main() {
  group('GoalMetric', () {
    test('every metric but workouts maps onto a chart metric', () {
      for (final metric in GoalMetric.values) {
        if (metric == GoalMetric.workouts) {
          expect(metric.chart, isNull);
          expect(metric.isWholeWorkout, isTrue);
        } else {
          expect(metric.chart, isNotNull, reason: '${metric.value} should have a chart query');
          expect(metric.chart!.value, metric.value);
        }
      }
    });

    test('pace is the only metric where lower is better', () {
      final descending = GoalMetric.values.where((m) => m.lowerIsBetter);
      expect(descending, [GoalMetric.averagePace]);
    });

    test('rejects an unknown metric', () {
      expect(() => GoalMetric.fromString('bodyWeight'), throwsArgumentError);
    });
  });

  group('GoalStage', () {
    test('rejects a non-positive target', () {
      expect(() => GoalStage.fromJson({'target': 0}), throwsArgumentError);
      expect(() => GoalStage.fromJson({'target': -5}), throwsArgumentError);
    });

    test('serialises dueOn as a calendar date, not an instant', () {
      final stage = GoalStage(target: 100, dueOn: DateTime(2026, 12, 25));
      expect(stage.toMap()['dueOn'], '2026-12-25');
    });

    test('omits absent fields', () {
      expect(GoalStage(target: 3).toMap(), {'target': 3});
    });

    test('isAchieved follows achievedAt', () {
      expect(GoalStage(target: 100).isAchieved, isFalse);
      expect(GoalStage(target: 100, achievedAt: DateTime.utc(2026, 7, 1)).isAchieved, isTrue);
    });
  });

  group('Goal', () {
    test('round-trips a staged ladder through toMap/fromJson', () {
      final goal = Goal(
        id: 'g-1',
        metric: GoalMetric.topSetWeight,
        exerciseId: 'e-1',
        stages: [
          GoalStage(id: 's-1', target: 100, dueOn: DateTime(2026, 12, 25)),
          GoalStage(id: 's-2', target: 140, dueOn: DateTime(2027, 12, 25)),
        ],
      );

      final parsed = Goal.fromJson(goal.toMap());

      expect(parsed.id, 'g-1');
      expect(parsed.metric, GoalMetric.topSetWeight);
      expect(parsed.exerciseId, 'e-1');
      expect(parsed.cadence, isNull);
      expect(parsed.stages.map((s) => s.target), [100, 140]);
      expect(parsed.stages.map((s) => s.id), ['s-1', 's-2']);
      expect(parsed.stages.first.dueOn, DateTime(2026, 12, 25));
    });

    test('parses a DB row, decoding stages from JSONB', () {
      final goal = Goal.fromRow({
        'id': 'g-1',
        'metric': 'workouts',
        'exercise_id': null,
        'cadence': 'week',
        'stages': '[{"id": "s-1", "target": 3}]',
        'archived': false,
        'created_at': DateTime.utc(2026, 7, 12),
      });

      expect(goal.metric, GoalMetric.workouts);
      expect(goal.exerciseId, isNull);
      expect(goal.cadence, GoalCadence.week);
      expect(goal.stages.single.target, 3);
      expect(goal.createdAt, DateTime.utc(2026, 7, 12));
    });

    test('currentStage is the first unachieved rung', () {
      final goal = Goal(
        metric: GoalMetric.topSetWeight,
        exerciseId: 'e-1',
        stages: [
          GoalStage(id: 's-1', target: 100, achievedAt: DateTime.utc(2026, 7, 1)),
          GoalStage(id: 's-2', target: 140),
        ],
      );

      expect(goal.currentStage?.id, 's-2');
      expect(goal.isComplete, isFalse);
    });

    test('a ladder is complete once every rung is achieved', () {
      final goal = Goal(
        metric: GoalMetric.topSetWeight,
        exerciseId: 'e-1',
        stages: [GoalStage(id: 's-1', target: 100, achievedAt: DateTime.utc(2026, 7, 1))],
      );

      expect(goal.currentStage, isNull);
      expect(goal.isComplete, isTrue);
    });

    test('a recurring goal is never complete', () {
      final goal = Goal(
        metric: GoalMetric.workouts,
        cadence: GoalCadence.week,
        stages: [GoalStage(id: 's-1', target: 3, achievedAt: DateTime.utc(2026, 7, 1))],
      );

      expect(goal.isComplete, isFalse);
    });
  });
}
