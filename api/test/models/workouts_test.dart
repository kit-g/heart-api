// ignore_for_file: avoid_dynamic_calls
import 'dart:convert';

import 'package:heart/models/workouts.dart';
import 'package:test/test.dart';

void main() {
  group('WorkoutRequest.toParams', () {
    test('extracts userId, name, parsed dates', () {
      final req = const WorkoutRequest(
        userId: 'u1',
        body: {
          'name': 'Push Day',
          'start': '2026-01-01T10:00:00Z',
          'end': '2026-01-01T11:30:00Z',
          'exercises': [],
        },
      );

      final params = req.toParams();
      expect(params['userId'], 'u1');
      expect(params['name'], 'Push Day');
      expect(params['startedAt'], DateTime.parse('2026-01-01T10:00:00Z'));
      expect(params['completedAt'], DateTime.parse('2026-01-01T11:30:00Z'));
    });

    test('accepts DateTime values directly for start/end', () {
      final start = DateTime.utc(2026, 1, 1);
      final req = WorkoutRequest(userId: 'u1', body: {'start': start, 'exercises': []});
      expect(req.toParams()['startedAt'], start);
    });

    test('returns null for missing/invalid date fields', () {
      final req = const WorkoutRequest(userId: 'u1', body: {'exercises': []});
      expect(req.toParams()['startedAt'], isNull);
      expect(req.toParams()['completedAt'], isNull);
    });

    test('exercises encoded with name flattened from {exercise: name} or {exercise: {name}}', () {
      final req = const WorkoutRequest(
        userId: 'u1',
        body: {
          'exercises': [
            {
              'exercise': 'Bench Press (Barbell)',
              'order': 0,
              'sets': [
                {'reps': 5},
              ],
            },
            {
              'exercise': {'name': 'Squat (Barbell)'},
              'order': 1,
              'sets': [],
            },
          ],
        },
      );

      final exercises = jsonDecode(req.toParams()['exercises'] as String) as List;
      expect(exercises, hasLength(2));
      expect(exercises[0], {
        'exercise_name': 'Bench Press (Barbell)',
        'order': 0,
        'unit_system': null,
        'sets': [
          {'reps': 5},
        ],
      });
      expect(exercises[1]['exercise_name'], 'Squat (Barbell)');
    });

    test('drops exercises whose name cannot be derived', () {
      final req = const WorkoutRequest(
        userId: 'u1',
        body: {
          'exercises': [
            {'exercise': null, 'order': 0, 'sets': []},
            {'exercise': 'Squat (Barbell)', 'order': 1, 'sets': []},
          ],
        },
      );

      final exercises = jsonDecode(req.toParams()['exercises'] as String) as List;
      expect(exercises, hasLength(1));
      expect(exercises.first['exercise_name'], 'Squat (Barbell)');
    });

    test('defaults sets to [] when missing', () {
      final req = const WorkoutRequest(
        userId: 'u1',
        body: {
          'exercises': [
            {'exercise': 'Squat (Barbell)', 'order': 0},
          ],
        },
      );

      final exercises = jsonDecode(req.toParams()['exercises'] as String) as List;
      expect(exercises.first['sets'], isEmpty);
    });

    test('exercises params is "[]" when body has no exercises', () {
      final req = const WorkoutRequest(userId: 'u1', body: {});
      expect(req.toParams()['exercises'], '[]');
    });
  });
}
