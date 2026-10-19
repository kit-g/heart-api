import 'package:heart_models/heart_models.dart';
import 'package:mockito/mockito.dart';
import 'package:test/test.dart';

import 'mocks.mocks.dart';

void main() {
  group('ExerciseSet.clearMeasurements', () {
    final start = DateTime.utc(2026, 10, 18, 9);

    MockExercise exerciseOf(Category category) {
      final exercise = MockExercise();
      when(exercise.category).thenReturn(category);
      return exercise;
    }

    test('unsets one measurement and keeps the others', () {
      final set = ExerciseSet(exerciseOf(.barbell), id: 's-1', start: start, weight: 60.0, reps: 5)
        ..clearMeasurements({.weight});

      expect(set.weight, isNull);
      expect(set.reps, 5);
    });

    test('writes as a set that never had the value', () {
      final barbell = exerciseOf(.barbell);
      final cleared = ExerciseSet(barbell, id: 's-1', start: start, weight: 60.0, reps: 5)
        ..clearMeasurements({.weight});
      final never = ExerciseSet(barbell, id: 's-1', start: start, reps: 5);

      expect(cleared.toMap(), never.toMap());
      expect(cleared.toMap(), isNot(contains('weight')));
      expect(cleared.toRow(), never.toRow());
    });

    test('its row carries the cleared column, so an update from it clears the stored value', () {
      final set = ExerciseSet(exerciseOf(.barbell), start: start, weight: 60.0, reps: 5)..clearMeasurements({.weight});

      expect(set.toRow(), containsPair('weight', null));
      expect(set.toRow(), containsPair('reps', 5));
    });

    test('clears several at once, and a later set fills them again', () {
      final set = ExerciseSet(exerciseOf(.cardio), start: start, duration: 600, distance: 2.0)
        ..clearMeasurements({.duration, .distance});

      expect(set.duration, isNull);
      expect(set.distance, isNull);

      set.setMeasurements(distance: 3.0);
      expect(set.distance, 3.0);
      expect(set.duration, isNull);
    });

    test('a field outside the category stays unset, and nothing else moves', () {
      final set = ExerciseSet(exerciseOf(.repsOnly), start: start, reps: 12)..clearMeasurements({.weight, .distance});

      expect(set.reps, 12);
      expect(set.weight, isNull);
      expect(set.distance, isNull);
    });

    test('an empty set of fields leaves the set alone', () {
      final set = ExerciseSet(exerciseOf(.dumbbell), start: start, weight: 20.0, reps: 8)..clearMeasurements({});

      expect(set.weight, 20.0);
      expect(set.reps, 8);
    });
  });

  group('ExerciseSet.setMeasurements', () {
    test('a null still keeps the value', () {
      final exercise = MockExercise();
      when(exercise.category).thenReturn(Category.machine);
      final set = ExerciseSet(exercise, weight: 40.0, reps: 10)..setMeasurements(reps: 12);

      expect(set.weight, 40.0);
      expect(set.reps, 12);
    });
  });
}
