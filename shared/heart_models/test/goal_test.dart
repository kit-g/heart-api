import 'package:heart_models/heart_models.dart';
import 'package:test/test.dart';

void main() {
  group('Goal.toBody', () {
    test('carries the definition, archived and the stages with their ids, never id or createdAt', () {
      final goal = Goal(
        id: 'g-1',
        metric: GoalMetric.topSetWeight,
        exerciseId: 'e-1',
        archived: true,
        createdAt: DateTime.utc(2026, 1, 1),
        stages: [
          GoalStage(id: 's-1', target: 100),
          GoalStage(target: 140),
        ],
      );

      expect(goal.toBody(), {
        'metric': 'topSetWeight',
        'exerciseId': 'e-1',
        'archived': true,
        'stages': [
          {'id': 's-1', 'target': 100},
          {'target': 140},
        ],
      });
    });

    test('a live recurring goal sends cadence and archived: false', () {
      final goal = Goal(metric: GoalMetric.workouts, cadence: GoalCadence.week, stages: [GoalStage(target: 3)]);

      expect(goal.toBody(), {
        'metric': 'workouts',
        'cadence': 'week',
        'archived': false,
        'stages': [
          {'target': 3},
        ],
      });
    });
  });

  group('GoalMetric', () {
    test('every metric but workouts and the subject counts maps onto a chart metric', () {
      for (final metric in GoalMetric.values) {
        if (metric == GoalMetric.workouts) {
          expect(metric.chart, isNull);
          expect(metric.isWholeWorkout, isTrue);
        } else if (metric.countsSubject) {
          expect(metric.chart, isNull);
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

    test('round-trips achievedBy through toMap/fromJson', () {
      final stage = GoalStage(
        id: 's-1',
        target: 100,
        achievedAt: DateTime.utc(2026, 7, 1),
        achievedBy: 'w-42',
      );
      final parsed = GoalStage.fromJson(stage.toMap());
      expect(parsed.achievedBy, 'w-42');
      expect(parsed.achievedAt, DateTime.utc(2026, 7, 1));
    });

    test('omits achievedBy when the rung is unattributed', () {
      expect(GoalStage(target: 100, achievedAt: DateTime.utc(2026, 7, 1)).toMap().containsKey('achievedBy'), isFalse);
    });

    test('copyWith carries achievedBy', () {
      final stage = GoalStage(target: 100, achievedBy: 'w-1');
      expect(stage.copyWith(target: 120).achievedBy, 'w-1');
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

  group('inDeadlineOrder', () {
    test('orders rungs by due date, not by target', () {
      final goal = Goal(
        metric: GoalMetric.cardioDistance,
        exerciseId: 'e-1',
        stages: [
          GoalStage(id: 'aug', target: 16, dueOn: DateTime(2026, 8)),
          GoalStage(id: 'dec', target: 12, dueOn: DateTime(2026, 12)),
        ],
      );

      // "16 by August" comes due before "12 by December" — timeline, not magnitude.
      expect(Goal.inDeadlineOrder(goal).stages.map((s) => s.id), ['aug', 'dec']);
    });

    test('a rung with no deadline sorts last', () {
      final goal = Goal(
        metric: GoalMetric.topSetWeight,
        exerciseId: 'e-1',
        stages: [
          GoalStage(id: 'someday', target: 200),
          GoalStage(id: 'christmas', target: 140, dueOn: DateTime(2026, 12, 25)),
        ],
      );

      expect(Goal.inDeadlineOrder(goal).stages.map((s) => s.id), ['christmas', 'someday']);
    });

    test('leaves a single-rung goal untouched', () {
      final goal = Goal(
        metric: GoalMetric.workouts,
        cadence: GoalCadence.week,
        stages: [GoalStage(id: 's-1', target: 3)],
      );

      expect(identical(Goal.inDeadlineOrder(goal), goal), isTrue);
    });
  });
  group('goals about a subject (heart-api#196)', () {
    test('sessions and sets are subject counts with no chart', () {
      for (final metric in [GoalMetric.sessions, GoalMetric.sets]) {
        expect(GoalMetric.fromString(metric.value), metric);
        expect(metric.countsSubject, isTrue);
        expect(metric.isWholeWorkout, isFalse);
        expect(metric.chart, isNull);
      }
      expect(GoalMetric.workouts.countsSubject, isFalse);
      expect(GoalMetric.topSetWeight.countsSubject, isFalse);
      expect(GoalMetric.topSetWeight.chart, ChartPreferenceType.topSetWeight);
    });

    test('a pattern or muscle goal round-trips through the wire and the row', () {
      final press = Goal.fromJson(const {
        'id': 'g1',
        'metric': 'sessions',
        'pattern': 'horizontal_press',
        'cadence': 'week',
        'stages': [
          {'id': 's1', 'target': 2},
        ],
      });
      expect(press.pattern, 'horizontal_press');
      expect(press.subject, const GoalSubject.pattern('horizontal_press'));
      expect(press.toMap(), containsPair('pattern', 'horizontal_press'));
      expect(press.toBody(), containsPair('pattern', 'horizontal_press'));
      expect(press.toMap().containsKey('muscle'), isFalse);

      final pull = Goal.fromRow({
        'id': 'g2',
        'metric': 'sets',
        'muscle': 'latissimus_dorsi',
        'cadence': 'week',
        'stages': [
          {'id': 's1', 'target': 12},
        ],
      });
      expect(pull.subject, const GoalSubject.muscle('latissimus_dorsi'));
      expect(pull.toBody(), containsPair('muscle', 'latissimus_dorsi'));
    });

    test('an exercise goal names its exercise as the subject; a workouts goal has none', () {
      final bench = Goal(metric: .sets, exerciseId: 'e1', stages: [GoalStage(target: 10)]);
      expect(bench.subject, const GoalSubject.exercise('e1'));
      expect(Goal(metric: .workouts, stages: [GoalStage(target: 3)]).subject, isNull);
    });

    test('a build that predates these metrics sets the goal aside, as readEach does', () {
      final goals = readEach(
        [
          {
            'metric': 'workouts',
            'stages': [
              {'target': 3},
            ],
          },
          {
            'metric': 'futureMetric',
            'pattern': 'hip_hinge',
            'stages': [
              {'target': 2},
            ],
          },
        ],
        Goal.fromJson,
      );
      expect(goals.items.single.metric, GoalMetric.workouts);
      expect(goals.unread.single['pattern'], 'hip_hinge');
    });
  });
}
