import 'package:heart_models/heart_models.dart';
import 'package:test/test.dart';

void main() {
  group('targets (heart-api#230)', () {
    test('reps in reserve sits beside the measures', () {
      final target = SetTarget.fromJson(const {
        'rir': 2,
        'reps': {'min': 8, 'max': 12},
      });
      expect(target.rir, 2);
      expect(target.toMap(), {
        'reps': {'min': 8, 'max': 12},
        'rir': 2,
      });
      expect(target.withRir(null).toMap().containsKey('rir'), isFalse);
      expect(target.withRange(.reps, null).rir, 2, reason: 'a measure change keeps the effort');
    });

    test('a capped AMRAP round-trips; an open top is the uncapped one', () {
      final capped = SetTarget.fromJson(const {
        'reps': {'min': 5, 'max': 10, 'amrap': true},
      });
      final range = capped[TargetMeasure.reps]!;
      expect(range.amrap, isTrue);
      expect(range.isAmrap, isTrue);
      expect(capped.toMap(), {
        'reps': {'min': 5, 'max': 10, 'amrap': true},
      });
      expect(const TargetRange(min: 5).isAmrap, isTrue);
      expect(const TargetRange(min: 8, max: 12).isAmrap, isFalse);
    });

    test('a range of a shape this build predates is still carried as it arrived', () {
      final target = SetTarget.fromJson(const {
        'reps': {'min': 5, 'tempo': '3-1-1'},
      });
      expect(target[TargetMeasure.reps], isNull);
      expect(target.toMap(), {
        'reps': {'min': 5, 'tempo': '3-1-1'},
      });
    });
  });

  group('rest (heart-api#230)', () {
    test('a template exercise carries its rest, and a workout started from it too', () {
      final template = Template.fromJson(const {
        'id': 't1',
        'order': 0,
        'exercises': [
          {
            'id': 'x1',
            'rest': 150,
            'exercise': {'id': 'e1', 'name': 'Squat', 'category': 'Barbell', 'target': 'Legs'},
            'sets': [
              {'id': 's1', 'reps': 5, 'weight': 100},
            ],
          },
        ],
      });
      expect(template.single.rest, 150);
      expect(template.single.toMap(), containsPair('rest', 150));
      expect(template.toWorkout().single.rest, 150);
    });

    test('clearing rest sends a null, which clears it; a build that never had it sends nothing', () {
      final exercise = WorkoutExercise.fromJson(const {
        'id': 'x1',
        'rest': 150,
        'exercise': {'id': 'e1', 'name': 'Squat', 'category': 'Barbell', 'target': 'Legs'},
        'sets': [],
      });
      exercise.rest = null;
      expect(exercise.toMap(), containsPair('rest', null));

      final fresh = WorkoutExercise.fromJson(const {
        'id': 'x2',
        'exercise': {'id': 'e1', 'name': 'Squat', 'category': 'Barbell', 'target': 'Legs'},
        'sets': [],
      });
      expect(fresh.toMap().containsKey('rest'), isFalse);
      final cleared = WorkoutExercise.fromJson(const {
        'id': 'x3',
        'rest': null,
        'exercise': {'id': 'e1', 'name': 'Squat', 'category': 'Barbell', 'target': 'Legs'},
        'sets': [],
      });
      expect(cleared.toMap(), containsPair('rest', null));
    });

    test('a request speaks about rest only when told to', () {
      expect(const TemplateExerciseRequest(exerciseId: 'e1', order: 0).toJson().containsKey('rest'), isFalse);
      expect(
        const TemplateExerciseRequest(exerciseId: 'e1', order: 0, rest: 90, setsRest: true).toJson(),
        containsPair('rest', 90),
      );
    });
  });
}
