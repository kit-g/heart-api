// ignore_for_file: avoid_dynamic_calls
import 'dart:convert';

import 'package:heart/models/errors.dart';
import 'package:heart/models/workouts.dart';
import 'package:test/test.dart';

// fixed v7 uuids — the only reference shape the input accepts since the id cutover
const _bench = '0198c1a2-b3c4-7d5e-8f60-718293a4b501';
const _squat = '0198c1a2-b3c4-7d5e-8f60-718293a4b502';

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

    test('carries calories and forwards per-exercise met', () {
      final req = const WorkoutRequest(
        userId: 'u1',
        body: {
          'calories': 512,
          'exercises': [
            {'exercise': _bench, 'order': 0, 'met': 5.5, 'sets': []},
            {'exercise': _squat, 'order': 1, 'sets': []},
          ],
        },
      );

      final params = req.toParams();
      expect(params['calories'], 512.0);

      final exercises = jsonDecode(params['exercises'] as String) as List;
      expect(exercises[0]['met'], 5.5);
      expect(exercises[1], isNot(contains('met')));
    });

    test('forwards a per-exercise note, trimmed, dropping blank ones', () {
      final req = const WorkoutRequest(
        userId: 'u1',
        body: {
          'exercises': [
            {'exercise': _bench, 'order': 0, 'note': '  do one hand at a time  ', 'sets': []},
            {'exercise': _squat, 'order': 1, 'note': '   ', 'sets': []},
          ],
        },
      );

      final exercises = jsonDecode(req.toParams()['exercises'] as String) as List;
      expect(exercises[0]['note'], 'do one hand at a time', reason: 'trimmed');
      expect(exercises[1], isNot(contains('note')), reason: 'a blank note is dropped, not stored');
    });

    test('rejects an over-long note with a 400', () {
      final req = WorkoutRequest(
        userId: 'u1',
        body: {
          'exercises': [
            {'exercise': _bench, 'order': 0, 'note': 'x' * 501, 'sets': []},
          ],
        },
      );

      expect(() => req.toParams(), throwsA(isA<BadRequest>()));
    });

    test('exercises encoded with the id flattened from {exercise: id} or {exercise: {id}}', () {
      final req = const WorkoutRequest(
        userId: 'u1',
        body: {
          'exercises': [
            {
              'exercise': _bench,
              'order': 0,
              'sets': [
                {'reps': 5},
              ],
            },
            {
              'exercise': {'id': _squat, 'name': 'Squat (Barbell)'},
              'order': 1,
              'sets': [],
            },
          ],
        },
      );

      final exercises = jsonDecode(req.toParams()['exercises'] as String) as List;
      expect(exercises, hasLength(2));
      expect(exercises[0], {
        'exercise_id': _bench,
        'order': 0,
        'sets': [
          {'reps': 5},
        ],
      });
      expect(exercises[1]['exercise_id'], _squat);
    });

    test('drops an exercise the user emptied, keeps the rest', () {
      final req = const WorkoutRequest(
        userId: 'u1',
        body: {
          'exercises': [
            {'exercise': null, 'order': 0, 'sets': []},
            {'exercise': _squat, 'order': 1, 'sets': []},
          ],
        },
      );

      final exercises = jsonDecode(req.toParams()['exercises'] as String) as List;
      expect(exercises, hasLength(1));
      expect(exercises.first['exercise_id'], _squat);
    });

    test('a present but malformed exercise reference is a 400, not a silent drop', () {
      final req = const WorkoutRequest(
        userId: 'u1',
        body: {
          'exercises': [
            {'exercise': 'Squat (Barbell)', 'order': 0, 'sets': []},
          ],
        },
      );

      expect(() => req.toParams(), throwsA(isA<BadRequest>()));
    });

    test('defaults sets to [] when missing', () {
      final req = const WorkoutRequest(
        userId: 'u1',
        body: {
          'exercises': [
            {'exercise': _squat, 'order': 0},
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
