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

    final rows = [
      exercise('bench', [
        for (var i = 0; i < 3; i++) set('w1', '2026-10-06T10:00:00.000Z'),
        for (var i = 0; i < 3; i++) set('w2', '2026-10-13T10:00:00.000Z'),
      ]),
      exercise('row', [for (var i = 0; i < 2; i++) set('w2', '2026-10-13T10:00:00.000Z')]),
      exercise('mine', [set('w1', '2026-10-06T10:00:00.000Z')]),
      exercise('bike', [set('w1', '2026-10-06T10:00:00.000Z')]),
      exercise('gone', [set('w1', '2026-10-06T10:00:00.000Z')]),
    ].toLensRows(library);

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
        'chest': {'sets': 3, 'sessions': 1},
        'arms': {'sets': 1.5, 'sessions': 1},
        'shoulders': {'sets': 2.5, 'sessions': 1},
      });
      expect(first['patterns'], {
        'horizontal_press': {'sets': 3, 'sessions': 1},
        'vertical_press': {'sets': 1, 'sessions': 1},
      });
      expect(first['unplacedSets'], 2);
      final second = weeks.last as Map;
      expect((second['muscles'] as Map)['back'], {'sets': 2, 'sessions': 1});
      expect(second.containsKey('unplacedSets'), isFalse);
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
  });
}
