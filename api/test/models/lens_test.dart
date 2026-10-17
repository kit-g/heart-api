import 'package:heart/models/changes.dart';
import 'package:heart/models/lens.dart';
import 'package:heart_models/heart_models.dart';
import 'package:test/test.dart';

void main() {
  group('LensWindow', () {
    // a Thursday
    final thursday = DateTime.utc(2026, 10, 15, 12);

    test('without from, the four weeks ending with to\'s, Monday first', () {
      final window = LensWindow.resolve(weekStart: DateTime.monday, to: thursday);
      expect(window.from, DateTime.utc(2026, 9, 21));
      expect(window.weeks, [
        DateTime.utc(2026, 9, 21),
        DateTime.utc(2026, 9, 28),
        DateTime.utc(2026, 10, 5),
        DateTime.utc(2026, 10, 12),
      ]);
    });

    test('weeks start on the user\'s day', () {
      final window = LensWindow.resolve(weekStart: DateTime.sunday, to: thursday);
      expect(window.weekOf(thursday), DateTime.utc(2026, 10, 11));
      expect(window.weeks.first, DateTime.utc(2026, 9, 20));
    });

    test('a given span reads every week it reaches, to exclusive', () {
      final window = LensWindow.resolve(
        weekStart: DateTime.monday,
        from: DateTime.utc(2026, 10, 7),
        to: DateTime.utc(2026, 10, 19),
      );
      expect(window.weeks, [DateTime.utc(2026, 10, 5), DateTime.utc(2026, 10, 12)]);
      expect(window.toMap(), {
        'weekStart': 1,
        'from': '2026-10-07T00:00:00.000Z',
        'to': '2026-10-19T00:00:00.000Z',
      });
    });
  });

  group('counts', () {
    const library = {
      'exercises': [
        {
          'id': 'bench',
          'target': 'Chest',
          'muscles': {
            'primary': {
              'ids': ['pectoralis_major_l', 'pectoralis_major_r'],
            },
            'secondary': {
              'ids': ['triceps_brachii_caput_longum_l', 'anterior_deltoid_l'],
            },
          },
          'movement': {
            'groups': ['horizontal_press'],
          },
        },
        {
          'id': 'row',
          'target': 'Back',
          'muscles': {
            'primary': {
              'ids': ['latissimus_dorsi_l'],
            },
          },
          'movement': {
            'groups': ['horizontal_row'],
          },
        },
        // made by the user: no tags, a target and a pattern they gave it
        {
          'id': 'mine',
          'target': 'Shoulders',
          'movement': {
            'groups': ['vertical_press'],
          },
        },
        {'id': 'bike', 'target': 'Cardio'},
      ],
    };
    final window = LensWindow.resolve(
      weekStart: DateTime.monday,
      from: DateTime.utc(2026, 10, 5),
      to: DateTime.utc(2026, 10, 19),
    );

    RecordSet set(String workoutId, String at) {
      return RecordSet(weight: 60, reps: 8, duration: null, distance: null, workoutId: workoutId, at: at);
    }

    ExerciseRecordSets exercise(String id, List<RecordSet> sets) {
      return (exerciseId: id, name: id, category: Category.barbell, sets: sets);
    }

    final sets = [
      exercise('bench', [
        for (var i = 0; i < 3; i++) set('w1', '2026-10-06T10:00:00.000Z'),
        for (var i = 0; i < 3; i++) set('w2', '2026-10-13T10:00:00.000Z'),
      ]),
      exercise('row', [for (var i = 0; i < 2; i++) set('w2', '2026-10-13T10:00:00.000Z')]),
      exercise('mine', [set('w1', '2026-10-06T10:00:00.000Z')]),
      exercise('bike', [set('w1', '2026-10-06T10:00:00.000Z')]),
      exercise('gone', [set('w1', '2026-10-06T10:00:00.000Z')]),
    ];
    final rows = sets.toLensRows(library);

    test('a row is one exercise\'s sets in one workout, with what it trains', () {
      expect(rows, hasLength(6));
      final mine = rows.firstWhere((row) => row.patterns.contains('vertical_press'));
      expect(mine.muscles, {MuscleGroupKey.shoulders: 1.0});
      expect(rows.where((row) => row.muscles.isEmpty && row.patterns.isEmpty), hasLength(2));
    });

    test('volume counts sets at their shares and sessions whole, week by week', () {
      final weeks = MeVolume.fold(window, rows).toMap()['weeks'] as List;
      final first = weeks.first as Map;
      expect(first['week'], '2026-10-05');
      expect(first['muscles'], {
        'chest': {'sets': 3, 'primarySets': 3, 'sessions': 1},
        'arms': {'sets': 1.5, 'primarySets': 0, 'sessions': 1},
        // the bench's secondary half sets, and the user's own press first
        'shoulders': {'sets': 2.5, 'primarySets': 1, 'sessions': 1},
      });
      expect(first['patterns'], {
        'horizontal_press': {'sets': 3, 'sessions': 1},
        'vertical_press': {'sets': 1, 'sessions': 1},
      });
      expect(first['unplacedSets'], 2);
      // six sets of 60 kg for 8
      expect(first['totalVolume'], 2880);
      final second = weeks.last as Map;
      expect((second['muscles'] as Map)['back'], {'sets': 2, 'primarySets': 2, 'sessions': 1});
      expect(second.containsKey('unplacedSets'), isFalse);
    });

    test('a week counts its finished workouts and their time', () {
      final spans = [
        (workoutId: 'w1', start: DateTime.utc(2026, 10, 6, 10), duration: const Duration(minutes: 45)),
        (workoutId: 'w2', start: DateTime.utc(2026, 10, 13, 10), duration: const Duration(minutes: 30)),
        (workoutId: 'w3', start: DateTime.utc(2026, 10, 14, 10), duration: const Duration(minutes: 30)),
      ];
      final weeks = MeVolume.fold(window, rows, spans: spans).toMap()['weeks'] as List;
      expect([for (final week in weeks.cast<Map>()) (week['workouts'], week['duration'])], [(1, 2700), (2, 3600)]);
    });

    test('untrained names every group no set reached in the window', () {
      expect(MeVolume.fold(window, rows).untrained, ['legs', 'adductors', 'hamstrings', 'glutes', 'neck', 'core']);
    });

    test('balance counts each side\'s sets and the weeks either was trained', () {
      final content = {
        'version': 1,
        'pairs': [
          {
            'key': 'push_pull',
            'left': {
              'key': 'push',
              'name': {'en': 'Push', 'fr': 'Poussée'},
              'patterns': ['horizontal_press', 'vertical_press'],
            },
            'right': {
              'key': 'pull',
              'name': {'en': 'Pull'},
              'patterns': ['horizontal_row', 'vertical_pull'],
            },
          },
          // a shape this server can't read is passed over
          {'key': 'later', 'left': 'abduction'},
        ],
      };

      final balance = MeBalance.fold(window, rows, content: content, locale: 'fr_CA').toMap();

      expect(balance['weeks'], 2);
      final pair = (balance['pairs'] as List).single as Map;
      expect(pair['key'], 'push_pull');
      expect(pair['left'], {
        'key': 'push',
        'name': 'Poussée',
        'patterns': ['horizontal_press', 'vertical_press'],
        'sets': 7,
      });
      expect((pair['right'] as Map)['name'], 'Pull');
      expect((pair['right'] as Map)['sets'], 2);
      expect(pair['weeksTrained'], 2);
    });

    test('no pairs while none are published', () {
      expect(MeBalance.fold(window, rows, content: null, locale: 'en').toMap()['pairs'], isEmpty);
    });

    group('goal progress', () {
      // the Thursday of the second week
      final now = DateTime.utc(2026, 10, 15, 12);

      Map<String, dynamic> measure(Goal goal, {List<WorkoutSpan> spans = const []}) {
        final progress = MeGoalProgress.measure(
          [goal],
          now: now,
          weekStart: DateTime.monday,
          sets: sets,
          rows: rows,
          spans: spans,
          library: library,
        );
        return (progress.toMap()['goals'] as List).single as Map<String, dynamic>;
      }

      Goal goal(
        GoalMetric metric,
        num target, {
        GoalCadence? cadence,
        String? exerciseId,
        String? pattern,
        String? muscle,
      }) {
        return Goal(
          metric: metric,
          cadence: cadence,
          exerciseId: exerciseId,
          pattern: pattern,
          muscle: muscle,
          stages: [GoalStage(target: target)],
        );
      }

      test('sets and sessions count the subject over its week', () {
        final chest = measure(goal(.sets, 6, cadence: .week, muscle: 'chest'));
        expect([chest['current'], chest['progress']], [3, 0.5]);
        expect(chest['period'], {'from': '2026-10-12T00:00:00.000Z', 'to': '2026-10-19T00:00:00.000Z'});
        final rowing = measure(goal(.sessions, 2, cadence: .week, pattern: 'horizontal_row'));
        expect([rowing['current'], rowing['progress']], [1, 0.5]);
        final bench = measure(goal(.sets, 6, exerciseId: 'bench'));
        expect(bench['current'], 6, reason: 'all time without a cadence');
        expect(bench.containsKey('period'), isFalse);
      });

      test('a muscle that is no group has nothing to read, as in the app', () {
        final triceps = measure(goal(.sets, 6, cadence: .week, muscle: 'triceps_brachii'));
        expect(triceps.containsKey('current'), isFalse);
        expect(triceps['progress'], 0);
      });

      test('an exercise milestone is its best session; a cadence folds the period', () {
        final e1rm = measure(goal(.estimatedOneRepMax, 80, exerciseId: 'bench'));
        expect(e1rm['current'], closeTo(74.5, 0.01));
        expect(e1rm['progress'], 0.93);
        expect(measure(goal(.topSetWeight, 100, cadence: .month, exerciseId: 'bench'))['current'], 60);
        expect(measure(goal(.totalVolume, 2000, cadence: .week, exerciseId: 'row'))['current'], 960);
        expect(measure(goal(.totalVolume, 2000, cadence: .week, exerciseId: 'gone'))['current'], 0);
      });

      test('a pace with no run in the period has nothing to read', () {
        final pace = measure(goal(.averagePace, 300, cadence: .week, exerciseId: 'bench'));
        expect(pace.containsKey('current'), isFalse);
        expect(pace['progress'], 0);
      });

      test('workouts count the finished ones; a finished ladder is all the way', () {
        final spans = [
          for (final day in [6, 13]) (workoutId: 'w$day', start: DateTime.utc(2026, 10, day), duration: Duration.zero),
        ];
        final total = measure(goal(.workouts, 10), spans: spans);
        expect([total['current'], total['progress']], [2, 0.2]);
        final done = Goal(
          metric: .workouts,
          stages: [GoalStage(target: 1, achievedAt: DateTime.utc(2026, 10, 6))],
        );
        expect(measure(done, spans: spans)['progress'], 1);
      });
    });
  });
}
