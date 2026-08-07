import 'package:heart/models/goals.dart';
import 'package:heart_models/heart_models.dart';
import 'package:test/test.dart';

void main() {
  group('GoalsResponse', () {
    test('toMap serializes each goal via toMap()', () {
      final response = GoalsResponse(
        goals: [
          Goal(
            id: 'g1',
            metric: GoalMetric.workouts,
            cadence: GoalCadence.week,
            stages: [GoalStage(target: 3)],
          ),
        ],
      );

      final goals = response.toMap()['goals'] as List;
      expect(goals, hasLength(1));
      final goal = goals.first as Map;
      expect(goal, containsPair('id', 'g1'));
      expect(goal, containsPair('metric', 'workouts'));
      expect(goal['stages'], [
        containsPair('target', 3),
      ]);
    });

    test('toMap emits an empty list for no goals', () {
      expect(GoalsResponse(goals: const []).toMap(), {'goals': isEmpty});
    });
  });
}
