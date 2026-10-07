import 'package:heart_models/heart_models.dart';
import 'package:test/test.dart';

/// The personal-records fold: every record must be the set it happened on —
/// value, its own companions, its workout and date — never independent maxima
/// glued together. Ported case for case from the app's local-database tests,
/// which this fold replaces the private copy of.
void main() {
  Map<String, dynamic> row({
    num? weight,
    num? reps,
    num? duration,
    num? distance,
    String workoutId = 'w1',
    String start = '2026-01-10T10:00:00Z',
  }) {
    return {
      'weight': weight,
      'reps': reps,
      'duration': duration,
      'distance': distance,
      'workout_id': workoutId,
      'start': start,
    };
  }

  Map<String, Object>? fold(String category, List<Map<String, dynamic>> rows) {
    return rows.map(RecordSet.fromRow).toList().toPersonalRecords(Category.fromString(category));
  }

  group('strength', () {
    test('each record carries its own set, workout and date', () {
      const category = 'Barbell';
      final rows = [
        // heaviest single, low reps
        row(weight: 100, reps: 3, workoutId: 'w1', start: '2026-01-01T10:00:00Z'),
        // best volume and best e1rm live on a different set
        row(weight: 90, reps: 10, workoutId: 'w2', start: '2026-02-01T10:00:00Z'),
        row(weight: 60, reps: 15, workoutId: 'w3', start: '2026-03-01T10:00:00Z'),
      ];

      final records = fold(category, rows)!;

      // the old query would have reported weight 100 next to reps 15 —
      // a set that never happened
      expect(records['heaviest'], {
        'weight': 100.0,
        'reps': 3,
        'workoutId': 'w1',
        'at': '2026-01-01T10:00:00Z',
        // the first session: nothing earlier to have beaten
      });
      expect(records['bestVolume'], {
        'value': 900.0,
        'weight': 90.0,
        'reps': 10,
        'workoutId': 'w2',
        'at': '2026-02-01T10:00:00Z',
        // 60×15 equals it later: the tie stays with w2, and w2 beat w1's 300
        'previous': {'value': 300.0, 'weight': 100.0, 'reps': 3, 'workoutId': 'w1', 'at': '2026-01-01T10:00:00Z'},
      });

      final oneRepMax = records['oneRepMax'] as Map;
      expect(oneRepMax['workoutId'], 'w2'); // 90×10 estimates higher than 100×3
      expect(oneRepMax['value'], closeTo(120.0, .1)); // 90 / (1.0278 − .278)

      expect(records['sessions'], 3);
      expect(records['firstAt'], '2026-01-01T10:00:00Z');
      expect(records['totalVolume'], 100.0 * 3 + 90 * 10 + 60 * 15);
    });

    test('rep maxes keep the best weight per rep count, first achievement wins ties', () {
      const category = 'Barbell';
      final rows = [
        row(weight: 100, reps: 5, workoutId: 'w1', start: '2026-01-01T10:00:00Z'),
        // same weight at the same reps later must not steal the record
        row(weight: 100, reps: 5, workoutId: 'w2', start: '2026-02-01T10:00:00Z'),
        row(weight: 110, reps: 3, workoutId: 'w2', start: '2026-02-01T10:00:00Z'),
        // 11+ reps stay out of the table
        row(weight: 40, reps: 20, workoutId: 'w3', start: '2026-03-01T10:00:00Z'),
      ];

      final records = fold(category, rows)!;
      expect(records['repMaxes'], [
        {'reps': 3, 'weight': 110.0, 'workoutId': 'w2', 'at': '2026-02-01T10:00:00Z'},
        {'reps': 5, 'weight': 100.0, 'workoutId': 'w1', 'at': '2026-01-01T10:00:00Z'},
      ]);
    });

    test('a heaviest set with null reps still counts, without inventing reps', () {
      const category = 'Dumbbell';
      final rows = [
        row(weight: 30, reps: 8, workoutId: 'w1'),
        row(weight: 40, reps: null, workoutId: 'w2'),
      ];

      final records = fold(category, rows)!;
      expect((records['heaviest'] as Map)['weight'], 40.0);
      expect((records['heaviest'] as Map).containsKey('reps'), isFalse);
      // volume/e1rm records need reps, so they come from the 30×8 set
      expect((records['bestVolume'] as Map)['weight'], 30.0);
    });
  });

  group('total volume', () {
    test('counts high-rep work that sets no rep max', () {
      const category = 'Barbell';
      final rows = [
        row(weight: 60, reps: 12, workoutId: 'w1'),
        row(weight: 50, reps: 15, workoutId: 'w2'),
      ];

      final records = fold(category, rows)!;
      expect(records.containsKey('repMaxes'), isFalse);
      expect(records['totalVolume'], 60.0 * 12 + 50 * 15);
    });
  });

  group('other categories', () {
    test('reps only', () {
      const category = 'Reps Only';
      final rows = [
        row(reps: 10, workoutId: 'w1', start: '2026-01-01T10:00:00Z'),
        row(reps: 14, workoutId: 'w2', start: '2026-02-01T10:00:00Z'),
      ];

      final records = fold(category, rows)!;
      expect(records['mostReps'], {
        'reps': 14,
        'workoutId': 'w2',
        'at': '2026-02-01T10:00:00Z',
        'previous': {'reps': 10, 'workoutId': 'w1', 'at': '2026-01-01T10:00:00Z'},
      });
      expect(records['totalReps'], 24);
    });

    test('assisted body weight treats less assistance as the record', () {
      const category = 'Assisted Body Weight';
      final rows = [
        row(weight: 20, reps: 8, workoutId: 'w1'),
        row(weight: 10, reps: 5, workoutId: 'w2'),
      ];

      final records = fold(category, rows)!;
      expect((records['lightestAssistance'] as Map)['weight'], 10.0);
      expect((records['mostReps'] as Map)['reps'], 8);
    });

    test('duration', () {
      const category = 'Duration';
      final rows = [
        row(duration: 60, workoutId: 'w1'),
        row(duration: 90, workoutId: 'w2'),
      ];

      final records = fold(category, rows)!;
      expect((records['longestDuration'] as Map)['duration'], 90.0);
      expect(records['totalDuration'], 150.0);
    });

    test('cardio: distance, duration and pace can come from different sets', () {
      const category = 'Cardio';
      final rows = [
        // 5 km in 30 min: longest distance, but slower
        row(distance: 5, duration: 1800, workoutId: 'w1', start: '2026-01-01T10:00:00Z'),
        // 2 km in 600 s: best pace
        row(distance: 2, duration: 600, workoutId: 'w2', start: '2026-02-01T10:00:00Z'),
      ];

      final records = fold(category, rows)!;
      expect((records['longestDistance'] as Map)['distance'], 5.0);
      expect((records['longestDuration'] as Map)['duration'], 1800.0);
      expect(records['bestPace'], {
        'pace': 300.0,
        'distance': 2.0,
        'duration': 600.0,
        'workoutId': 'w2',
        'at': '2026-02-01T10:00:00Z',
        'previous': {
          'pace': 360.0,
          'distance': 5.0,
          'duration': 1800.0,
          'workoutId': 'w1',
          'at': '2026-01-01T10:00:00Z',
        },
      });
      expect(records['totalDistance'], 7.0);
    });

    test('carry: the heaviest load and the farthest walk are each their own set', () {
      const category = 'Weighted Distance';
      final rows = [
        // heavy and short
        row(weight: 60, distance: 0.02, workoutId: 'w1', start: '2026-01-01T10:00:00Z'),
        // light and long
        row(weight: 30, distance: 0.08, workoutId: 'w2', start: '2026-02-01T10:00:00Z'),
      ];

      final records = fold(category, rows)!;
      expect(records['heaviest'], {
        'weight': 60.0,
        'distance': 0.02,
        'workoutId': 'w1',
        'at': '2026-01-01T10:00:00Z',
        // February's lighter carry came after; it can't be what January beat
      });
      expect((records['longestDistance'] as Map)['distance'], 0.08);
      expect((records['longestDistance'] as Map)['weight'], 30.0);
      expect(records['totalDistance'], closeTo(0.1, 1e-9));
      // weight × distance stays off the records, and so do reps
      expect(records.containsKey('bestVolume'), isFalse);
      expect(records.containsKey('mostReps'), isFalse);
    });

    test('loaded hold: the heaviest load and the longest hold', () {
      const category = 'Weighted Duration';
      final rows = [
        row(weight: 20, duration: 60, workoutId: 'w1', start: '2026-01-01T10:00:00Z'),
        row(weight: 10, duration: 120, workoutId: 'w2', start: '2026-02-01T10:00:00Z'),
      ];

      final records = fold(category, rows)!;
      expect((records['heaviest'] as Map)['weight'], 20.0);
      expect((records['heaviest'] as Map)['duration'], 60.0);
      expect((records['longestDuration'] as Map)['duration'], 120.0);
      expect((records['longestDuration'] as Map)['weight'], 10.0);
      expect(records['totalDuration'], 180.0);
    });
  });

  group('previous', () {
    test('only counts sessions before the record', () {
      const category = 'Barbell';
      final rows = [
        row(weight: 100, reps: 1, workoutId: 'jan', start: '2026-01-01T10:00:00Z'),
        row(weight: 95, reps: 1, workoutId: 'mar', start: '2026-03-01T10:00:00Z'),
      ];

      final heaviest = fold(category, rows)!['heaviest'] as Map;
      expect(heaviest['workoutId'], 'jan');
      expect(heaviest.containsKey('previous'), isFalse, reason: 'a record cannot have beaten a later set');
    });

    test('is the record with its own session left out', () {
      const category = 'Barbell';
      final rows = [
        row(weight: 80, reps: 5, workoutId: 'w1', start: '2026-01-01T10:00:00Z'),
        row(weight: 95, reps: 2, workoutId: 'w2', start: '2026-02-01T10:00:00Z'),
        // this session's two sets: the second is the record, and the first
        // must not stand in for what it beat
        row(weight: 90, reps: 5, workoutId: 'w3', start: '2026-03-01T10:00:00Z'),
        row(weight: 100, reps: 3, workoutId: 'w3', start: '2026-03-01T10:00:00Z'),
      ];

      final records = fold(category, rows)!;
      final heaviest = records['heaviest'] as Map;
      expect(heaviest['workoutId'], 'w3');
      expect((heaviest['previous'] as Map)['weight'], 95.0);
      expect((heaviest['previous'] as Map).containsKey('previous'), isFalse);
      // rep maxes are a table, not a headline, and carry none
      expect((records['repMaxes'] as List).every((each) => !(each as Map).containsKey('previous')), isTrue);
    });

    test('is absent when only one session has the exercise', () {
      const category = 'Barbell';
      final rows = [
        row(weight: 60, reps: 8, workoutId: 'w1'),
        row(weight: 70, reps: 5, workoutId: 'w1'),
      ];

      final records = fold(category, rows)!;
      for (final key in ['heaviest', 'oneRepMax', 'bestVolume']) {
        expect((records[key] as Map).containsKey('previous'), isFalse, reason: key);
      }
    });

    test('is absent when the other sessions never measured that value', () {
      const category = 'Cardio';
      final rows = [
        // duration only: no distance, so no pace to beat
        row(duration: 1200, workoutId: 'w1'),
        row(distance: 5, duration: 1500, workoutId: 'w2'),
      ];

      final records = fold(category, rows)!;
      expect((records['bestPace'] as Map).containsKey('previous'), isFalse);
      expect((records['longestDuration'] as Map)['previous'], {
        'duration': 1200.0,
        'workoutId': 'w1',
        'at': '2026-01-10T10:00:00Z',
      });
    });
  });

  group('degenerate inputs', () {
    test('never performed yields null', () {
      const category = 'Barbell';
      final rows = <Map<String, dynamic>>[];
      expect(fold(category, rows), isNull);
    });

    test('rows with only nulls yield null, not an empty records card', () {
      const category = 'Barbell';
      final rows = [row(weight: null, reps: null)];
      expect(fold(category, rows), isNull);
    });
  });

  /// A session's chart values: the app's per-dimension history queries
  /// (heart_db's metrics.dart), one session at a time.
  group('foldSession', () {
    Map<String, num> session(String category, List<Map<String, dynamic>> rows) {
      return foldSession(Category.fromString(category), rows.map(RecordSet.fromRow).toList());
    }

    test('a strength session gives every strength dimension', () {
      final metrics = session('Barbell', [row(weight: 100, reps: 5), row(weight: 110, reps: 3)]);

      expect(
        metrics.keys,
        unorderedEquals([
          'topSetWeight',
          'estimatedOneRepMax',
          'totalVolume',
          'averageWorkingWeight',
          'totalReps',
          'maxConsecutiveReps',
        ]),
      );
      expect(metrics['topSetWeight'], 110);
      // the best estimate is the triple's, not the five's
      expect(metrics['estimatedOneRepMax'], closeTo(110 / (1.0278 - .0278 * 3), 1e-9));
      expect(metrics['totalVolume'], 830);
      expect(metrics['averageWorkingWeight'], 830 / 8);
      expect(metrics['totalReps'], 8);
      expect(metrics['maxConsecutiveReps'], 5);
    });

    test('bodyweight sets weigh nothing, and leave no estimate', () {
      final metrics = session('Weighted Body Weight', [row(reps: 12), row(reps: 10)]);

      expect(metrics['topSetWeight'], 0);
      expect(metrics['totalVolume'], 0);
      expect(metrics['averageWorkingWeight'], 0);
      expect(metrics['totalReps'], 22);
      expect(metrics.containsKey('estimatedOneRepMax'), isFalse);
    });

    test('an estimate past 36 reps is left out, as the records leave it', () {
      final metrics = session('Dumbbell', [row(weight: 10, reps: 40)]);

      expect(metrics.containsKey('estimatedOneRepMax'), isFalse);
      expect(metrics['topSetWeight'], 10);
    });

    test('sets without reps give no average or best set', () {
      final metrics = session('Machine', [row(weight: 50)]);

      expect(metrics['topSetWeight'], 50);
      expect(metrics['totalReps'], 0);
      expect(metrics.containsKey('averageWorkingWeight'), isFalse);
      expect(metrics.containsKey('maxConsecutiveReps'), isFalse);
    });

    test('only the dimensions the category charts', () {
      expect(session('Reps Only', [row(reps: 8), row(reps: 6)]), {'maxConsecutiveReps': 8, 'totalReps': 14});
      expect(session('Duration', [row(duration: 60), row(duration: 45)]), {'totalTimeUnderTension': 105});
    });

    test('assistance is the lightest set: less is the improvement', () {
      final metrics = session('Assisted Body Weight', [row(weight: 30, reps: 5), row(weight: 20, reps: 4)]);

      expect(metrics['assistanceWeight'], 20);
      expect(metrics['topSetWeight'], 30);
    });

    test('cardio sums, and has a pace only with distance', () {
      expect(session('Cardio', [row(distance: 2, duration: 600), row(distance: 3, duration: 900)]), {
        'cardioDistance': 5,
        'cardioDuration': 1500,
        'averagePace': 300,
      });
      expect(session('Cardio', [row(duration: 1200)]), {'cardioDistance': 0, 'cardioDuration': 1200});
    });

    test('no sets, no values', () {
      expect(session('Barbell', []), isEmpty);
    });
  });
}
