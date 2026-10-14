import 'package:heart_models/heart_models.dart';
import 'package:test/test.dart';

void main() {
  group('slots (heart-api#232)', () {
    test('a share can be of another exercise\'s base', () {
      final target = SetTarget.fromJson(const {
        'share': 0.6,
        'of': 'squat',
        'reps': {'min': 5, 'max': 5},
      });
      expect(target.of, 'squat');
      expect(target.toMap(), containsPair('of', 'squat'));
      expect(target.withOf(null).toMap().containsKey('of'), isFalse);
      expect(target.withShare(0.65).of, 'squat');
    });

    test('a supplemental wave set round-trips and stays out of the way', () {
      final rule = GrowthRule.fromJson(const {
        'kind': 'shareOfMax',
        'step': 5,
        'waves': [
          [
            {'share': 0.65, 'reps': 5},
            {'share': 0.85, 'reps': 5, 'amrap': true},
            {'share': 0.65, 'reps': 5, 'supplemental': true},
          ],
        ],
      }) as ShareOfMax;
      expect(rule.week(1).map((set) => set.supplemental), [false, false, true]);
      expect(rule.toMap()['waves'], [
        [
          {'share': 0.65, 'reps': 5},
          {'share': 0.85, 'reps': 5, 'amrap': true},
          {'share': 0.65, 'reps': 5, 'supplemental': true},
        ],
      ]);
      expect(
        () => WaveSet.fromJson(const {'share': 0.5, 'reps': 5, 'supplemental': 'yes'}),
        throwsArgumentError,
      );
    });

    test('a base can belong to one occurrence of a lift, and the current ones keep apart', () {
      final heavy = ProgramBase(exerciseId: 'bench', slot: 'monday', value: 100, at: DateTime.utc(2026, 10, 1));
      final light = ProgramBase(exerciseId: 'bench', slot: 'thursday', value: 80, at: DateTime.utc(2026, 10, 2));
      final own = ProgramBase(exerciseId: 'bench', value: 90, at: DateTime.utc(2026, 10, 3));
      expect(ProgramBase.fromJson(heavy.toMap()).slot, 'monday');
      final current = currentBases([heavy, light, own]);
      expect(current['monday']?.value, 100);
      expect(current['thursday']?.value, 80);
      expect(current['bench']?.value, 90);
    });

    test('an open slot names its pattern and a total of reps, carried into a workout', () {
      final template = Template.fromJson(const {
        'id': 't1',
        'order': 0,
        'exercises': [
          {
            'id': 'x1',
            'pattern': 'vertical_pull',
            'totalReps': {'min': 50, 'max': 100},
            'exercise': {'id': 'e1', 'name': 'Chin-up', 'category': 'Weighted Body Weight', 'target': 'Back'},
            'sets': [
              {'id': 's1', 'reps': 10},
            ],
          },
        ],
      });
      final slot = template.single;
      expect(slot.pattern, 'vertical_pull');
      expect(slot.totalReps, const TargetRange(min: 50, max: 100));
      expect(slot.toMap(), containsPair('totalReps', {'min': 50, 'max': 100}));
      expect(template.toWorkout().single.pattern, 'vertical_pull');
    });

    test('an open slot and a total clear by sending null', () {
      final exercise = WorkoutExercise.fromJson(const {
        'id': 'x1',
        'pattern': 'vertical_pull',
        'totalReps': {'min': 50, 'max': 100},
        'exercise': {'id': 'e1', 'name': 'Pull-up', 'category': 'Reps Only', 'target': 'Back'},
        'sets': [],
      });
      exercise
        ..pattern = null
        ..totalReps = null;
      expect(exercise.toMap(), allOf(containsPair('pattern', null), containsPair('totalReps', null)));
    });

    test('a total in a shape this build predates is carried, not a failed read', () {
      final exercise = WorkoutExercise.fromJson(const {
        'id': 'x1',
        'totalReps': {'min': 50, 'per': 'side'},
        'exercise': {'id': 'e1', 'name': 'Pull-up', 'category': 'Reps Only', 'target': 'Back'},
        'sets': [],
      });
      expect(exercise.totalReps, isNull);
      expect(exercise.toMap(), containsPair('totalReps', {'min': 50, 'per': 'side'}));

      exercise.totalReps = const TargetRange(min: 40, max: 60);
      expect(exercise.toMap(), containsPair('totalReps', {'min': 40, 'max': 60}));
    });
  });
}
