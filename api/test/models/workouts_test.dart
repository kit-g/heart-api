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

    test('a note is measured in characters, as the column measures it', () {
      final req = WorkoutRequest(
        userId: 'u1',
        body: {
          'exercises': [
            // 500 code points, 1000 UTF-16 units
            {'exercise': _bench, 'order': 0, 'note': '💪' * 500, 'sets': []},
          ],
        },
      );
      expect(() => req.toParams(), returnsNormally);
    });

    test('the workout note is trimmed, blank is none, and whether the key came is kept apart', () {
      WorkoutRequest body(Map<String, dynamic> extra) => WorkoutRequest(userId: 'u1', body: {'name': 'W', ...extra});

      expect(body({'note': '  felt strong '}).toParams()['note'], 'felt strong');
      expect(body({'note': '   '}).toParams()['note'], isNull);
      expect(body({'note': null}).setsNote, isTrue);
      expect(body({}).setsNote, isFalse);
      expect(body({}).toParams()['note'], isNull);
    });

    test('the workout note is at most 1000 code points', () {
      final fits = WorkoutRequest(userId: 'u1', body: {'note': '💪' * 1000});
      expect(() => fits.toParams(), returnsNormally);

      final over = WorkoutRequest(userId: 'u1', body: {'note': 'x' * 1001});
      expect(
        () => over.toParams(),
        throwsA(isA<BadRequest>().having((e) => e.code, 'code', 'workout_note_too_long')),
      );
      final notText = const WorkoutRequest(userId: 'u1', body: {'note': 7});
      expect(() => notText.toParams(), throwsA(isA<BadRequest>()));
    });

    test('two exercises at one order are a 400: sets find their exercise by it', () {
      final req = const WorkoutRequest(
        userId: 'u1',
        body: {
          'exercises': [
            {'exercise': _bench, 'order': 0, 'sets': []},
            {'exercise': _squat, 'order': 0, 'sets': []},
          ],
        },
      );
      expect(
        () => req.toParams(),
        throwsA(isA<BadRequest>().having((e) => e.code, 'code', 'duplicate_order')),
      );
    });

    test('an id named twice in one payload is a 400, not a silently dropped entry', () {
      const id = '0198c1a2-b3c4-7d5e-8f60-718293a4b5ff';
      WorkoutRequest body(List<Map<String, dynamic>> exercises) =>
          WorkoutRequest(userId: 'u1', body: {'exercises': exercises});
      final twiceExercise = body([
        {'id': id, 'exercise': _bench, 'order': 0, 'sets': <Map>[]},
        {'id': id, 'exercise': _squat, 'order': 1, 'sets': <Map>[]},
      ]);
      final twiceSet = body([
        {
          'exercise': _bench,
          'order': 0,
          'sets': [
            {'id': id, 'weight': 100},
            {'id': id, 'weight': 105},
          ],
        },
      ]);
      for (final req in [twiceExercise, twiceSet]) {
        expect(
          () => req.toParams(),
          throwsA(isA<BadRequest>().having((e) => e.code, 'code', 'duplicate_id')),
        );
      }
    });

    group('set type and RPE', () {
      List sets(List<Map<String, dynamic>> raw) {
        final req = WorkoutRequest(
          userId: 'u1',
          body: {
            'exercises': [
              {'exercise': _bench, 'order': 0, 'sets': raw},
            ],
          },
        );
        return (jsonDecode(req.toParams()['exercises'] as String) as List).single['sets'] as List;
      }

      test('valid values are forwarded as their wire word, an explicit null as normal', () {
        expect(
          sets([
            {'weight': 60, 'set_type': 'warmup', 'rpe': 6.5},
            {'weight': 100, 'set_type': null, 'rpe': null},
            {'weight': 105, 'set_type': 'normal'},
          ]),
          [
            {'weight': 60, 'set_type': 'warmup', 'rpe': 6.5},
            // an explicit null clears the type, which is a normal set
            {'weight': 100, 'set_type': 'normal', 'rpe': null},
            {'weight': 105, 'set_type': 'normal'},
          ],
        );
      });

      test('absent keys stay absent — the replace keeps what is stored', () {
        expect(
          sets([
            {'weight': 100, 'reps': 5},
          ]).single,
          {'weight': 100, 'reps': 5},
        );
      });

      test('an unknown set type is a 400 naming the set', () {
        expect(
          () => sets([
            {'weight': 100},
            {'weight': 100, 'set_type': 'amrap'},
          ]),
          throwsA(
            isA<BadRequest>()
                .having((e) => e.code, 'code', 'invalid_set_type')
                .having((e) => e.reason, 'reason', contains('exercises[0].sets[1]')),
          ),
        );
      });

      test('an RPE off the 1-10 half-step scale is a 400', () {
        for (final rpe in [8.3, 11, 0.5, '8']) {
          expect(
            () => sets([
              {'weight': 100, 'rpe': rpe},
            ]),
            throwsA(isA<BadRequest>().having((e) => e.code, 'code', 'invalid_rpe')),
            reason: '$rpe',
          );
        }
      });
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

    /// Sets with nothing to hang them on used to be dropped as quietly as an
    /// emptied editor row, which made a malformed payload indistinguishable
    /// from `exercises: []` — and `_replaceWorkout` empties on that.
    test('sets with no exercise reference are a 400, not a silent drop', () {
      final req = const WorkoutRequest(
        userId: 'u1',
        body: {
          'exercises': [
            {
              'order': 0,
              'sets': [
                {'weight': 100, 'reps': 5},
              ],
            },
          ],
        },
      );

      expect(() => req.toParams(), throwsA(isA<BadRequest>()));
    });

    test('an explicitly null exercise carrying sets is also a 400', () {
      final req = const WorkoutRequest(
        userId: 'u1',
        body: {
          'exercises': [
            {
              'exercise': null,
              'order': 0,
              'sets': [
                {'weight': 100, 'reps': 5},
              ],
            },
          ],
        },
      );

      expect(() => req.toParams(), throwsA(isA<BadRequest>()));
    });

    test('a wholly empty row is still dropped — the app serializes one that way', () {
      // WorkoutExercise.toMap() writes `exercise` off its first set, so a row
      // the user emptied arrives as {id, start, sets: []} with no exercise.
      final req = const WorkoutRequest(
        userId: 'u1',
        body: {
          'exercises': [
            {'id': '0198c1a2-b3c4-7d5e-8f60-718293a4b5aa', 'start': '2026-01-01T10:00:00Z', 'sets': []},
            {'exercise': _bench, 'order': 1, 'sets': []},
          ],
        },
      );

      final exercises = jsonDecode(req.toParams()['exercises'] as String) as List;
      expect(exercises, hasLength(1));
      expect(exercises.first['exercise_id'], _bench);
    });
  });

  group('WorkoutRequest — pauses', () {
    WorkoutRequest body(Map<String, dynamic> extra) => WorkoutRequest(userId: 'u1', body: {'name': 'W', ...extra});
    List stored(Map<String, dynamic> extra) => jsonDecode(body(extra).toParams()['pauses'] as String) as List;
    Matcher invalid(String reason) => throwsA(
      isA<BadRequest>().having((e) => e.code, 'code', 'invalid_pauses').having((e) => e.reason, 'reason', reason),
    );

    test('absent or null is none, and whether the key came is kept apart', () {
      expect(stored({}), isEmpty);
      expect(stored({'pauses': null}), isEmpty);
      expect(body({}).setsPauses, isFalse);
      expect(body({'pauses': []}).setsPauses, isTrue);
    });

    test('stored as UTC instants, sorted by start; touching ends are fine', () {
      expect(
        stored({
          'pauses': [
            {'start': '2026-10-03T20:20:00+02:00', 'end': '2026-10-03T18:25:00Z'},
            {'start': '2026-10-03T18:10:00Z', 'end': '2026-10-03T18:20:00Z'},
          ],
        }),
        [
          {'start': '2026-10-03T18:10:00.000Z', 'end': '2026-10-03T18:20:00.000Z'},
          {'start': '2026-10-03T18:20:00.000Z', 'end': '2026-10-03T18:25:00.000Z'},
        ],
      );
    });

    test('a pause that does not end after it starts is a 400 naming it', () {
      expect(
        () => stored({
          'pauses': [
            {'start': '2026-10-03T18:10:00Z', 'end': '2026-10-03T18:10:00Z'},
          ],
        }),
        invalid('pauses[0] must end after it starts'),
      );
    });

    test('a malformed pause is a 400 naming it', () {
      for (final bad in [
        'yesterday',
        {'start': '2026-10-03T18:10:00Z'},
        {'start': '2026-10-03T18:10:00Z', 'end': 'later'},
        {'start': 1, 'end': 2},
      ]) {
        expect(
          () => stored({
            'pauses': [
              {'start': '2026-10-03T18:00:00Z', 'end': '2026-10-03T18:01:00Z'},
              bad,
            ],
          }),
          invalid('pauses[1] needs ISO-8601 start and end'),
          reason: '$bad',
        );
      }
      expect(() => stored({'pauses': {}}), invalid('pauses must be a list'));
    });

    test('overlapping pauses are a 400 naming the later one as sent', () {
      expect(
        () => stored({
          'pauses': [
            {'start': '2026-10-03T18:30:00Z', 'end': '2026-10-03T18:40:00Z'},
            {'start': '2026-10-03T18:10:00Z', 'end': '2026-10-03T18:35:00Z'},
          ],
        }),
        invalid('pauses[0] overlaps another pause'),
      );
    });

    test('at most 100', () {
      List<Map<String, String>> minutes(int n) => [
        for (var i = 0; i < n; i++)
          {
            'start': DateTime.utc(2026, 10, 3, 18, i).toIso8601String(),
            'end': DateTime.utc(2026, 10, 3, 18, i, 30).toIso8601String(),
          },
      ];
      expect(stored({'pauses': minutes(100)}), hasLength(100));
      expect(() => stored({'pauses': minutes(101)}), invalid('a workout has at most 100 pauses'));
    });
  });
}
