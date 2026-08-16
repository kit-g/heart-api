import 'package:heart_models/heart_models.dart';
import 'package:mockito/mockito.dart';
import 'package:test/test.dart';

import 'mocks.mocks.dart';

void main() {
  late MockExercise exercise;

  setUp(
    () {
      exercise = MockExercise();
      when(exercise.name).thenReturn('Bench Press');
      when(exercise.category).thenReturn(Category.barbell);
      when(exercise.target).thenReturn(Target.chest);
    },
  );

  Map<String, dynamic> row(String exerciseId) {
    return {
      'workoutId': 'workout-1',
      'workoutName': 'Push day',
      'exerciseId': exerciseId,
      'id': 'set-1',
      'started_at': '2025-01-21T12:00:00Z',
      'reps': 8,
      'weight': 100.0,
    };
  }

  group(
    'ExerciseAct',
    () {
      test(
        'start is recovered from a Firebase-era sanitized timestamp id',
        () {
          final act = ExerciseAct.fromRows(exercise, [row('2025-01-21T12:00:00_000Z')]);

          expect(act.start, equals(DateTime.parse('2025-01-21T12:00:00.000Z')));
        },
      );

      test(
        'start is recovered from a v7 uuid id',
        () {
          final id = uuidV7();
          final act = ExerciseAct.fromRows(exercise, [row(id)]);

          expect(act.start, equals(timestampOfUuidV7(id)));
        },
      );

      test(
        'an unrecognizable id yields no start',
        () {
          final act = ExerciseAct.fromRows(exercise, [row('neither-era')]);

          expect(act.start, isNull);
        },
      );
    },
  );
}
