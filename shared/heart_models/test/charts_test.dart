import 'package:heart_models/heart_models.dart';
import 'package:test/test.dart';

void main() {
  group('ChartPreferenceType.isDuration', () {
    test('cardio duration and time under tension are the durations', () {
      final durations = ChartPreferenceType.values.where((each) => each.isDuration);
      expect(
        durations,
        unorderedEquals([ChartPreferenceType.cardioDuration, ChartPreferenceType.totalTimeUnderTension]),
      );
    });
  });

  group('ChartPreferenceType.periodAggregate', () {
    test('totals sum, peaks take the best, averages take the mean', () {
      const sums = [
        ChartPreferenceType.totalVolume,
        ChartPreferenceType.totalReps,
        ChartPreferenceType.totalTimeUnderTension,
        ChartPreferenceType.cardioDistance,
        ChartPreferenceType.cardioDuration,
      ];
      const bests = [
        ChartPreferenceType.topSetWeight,
        ChartPreferenceType.estimatedOneRepMax,
        ChartPreferenceType.maxConsecutiveReps,
        ChartPreferenceType.assistanceWeight,
      ];
      const means = [ChartPreferenceType.averageWorkingWeight, ChartPreferenceType.averagePace];

      for (final each in sums) {
        expect(each.periodAggregate, PeriodAggregate.sum, reason: each.value);
      }
      for (final each in bests) {
        expect(each.periodAggregate, PeriodAggregate.best, reason: each.value);
      }
      for (final each in means) {
        expect(each.periodAggregate, PeriodAggregate.mean, reason: each.value);
      }
      expect([...sums, ...bests, ...means], unorderedEquals(ChartPreferenceType.values));
    });
  });

  group('PeriodAggregate.of', () {
    test('folds a period\'s sessions', () {
      expect(PeriodAggregate.sum.of([100, 120, 80]), 300);
      expect(PeriodAggregate.best.of([100, 120, 80]), 120);
      expect(PeriodAggregate.mean.of([100, 120, 80]), 100);
    });

    test('a single session is its own aggregate', () {
      for (final each in PeriodAggregate.values) {
        expect(each.of([42]), 42, reason: each.name);
      }
    });

    test('an empty period has no aggregate', () {
      for (final each in PeriodAggregate.values) {
        expect(() => each.of([]), throwsStateError, reason: each.name);
      }
    });
  });

  group('ChartPreference', () {
    test('ChartPreference.fromRow works with topSetWeight', () {
      final row = {
        'id': '1',
        'type': 'topSetWeight',
        'data': '{"exerciseName": "Bench Press"}',
      };
      final pref = ChartPreference.fromRow(row);

      expect(pref.id, '1');
      expect(pref.type, ChartPreferenceType.topSetWeight);
      expect(pref.exerciseName, 'Bench Press');
    });

    test('ChartPreference.fromRow works with null data', () {
      final row = {
        'id': '2',
        'type': 'maxConsecutiveReps',
        'data': null,
      };
      final pref = ChartPreference.fromRow(row);

      expect(pref.id, '2');
      expect(pref.type, ChartPreferenceType.maxConsecutiveReps);
      expect(pref.data, isNull);
    });

    test('ChartPreference.topSetWeight factory works', () {
      final pref = ChartPreference.exercise('Squat', .topSetWeight);

      expect(pref.id, isNull);
      expect(pref.type, ChartPreferenceType.topSetWeight);
      expect(pref.exerciseName, 'Squat');
    });

    test('toRow works', () {
      final pref = ChartPreference.exercise('Deadlift', .topSetWeight);
      final row = pref.toRow();

      expect(row['id'], isNull);
      expect(row['type'], 'topSetWeight');
      expect(row['data'], '{"exerciseName":"Deadlift"}');
    });

    test('copyWith works', () {
      final pref = ChartPreference.exercise('Bench Press', .topSetWeight);
      final updated = pref.copyWith(id: 'new-id');

      expect(updated.id, 'new-id');
      expect(updated.type, pref.type);
      expect(updated.exerciseName, pref.exerciseName);
    });
  });

  group('ChartPreferenceType', () {
    test('fromString works', () {
      expect(ChartPreferenceType.fromString('topSetWeight'), ChartPreferenceType.topSetWeight);
      expect(ChartPreferenceType.fromString('maxConsecutiveReps'), ChartPreferenceType.maxConsecutiveReps);
    });

    test('fromString throws on invalid value', () {
      expect(() => ChartPreferenceType.fromString('invalid'), throwsArgumentError);
    });

    test('every category has charts', () {
      for (final category in Category.values) {
        expect(ChartPreferenceType.chartsByExerciseCategory(category), isNotEmpty, reason: '$category');
      }
    });

    test('weighted distance and duration chart the load and its distance or time', () {
      expect(
        ChartPreferenceType.chartsByExerciseCategory(.weightedDistance),
        [ChartPreferenceType.topSetWeight, ChartPreferenceType.cardioDistance],
      );
      expect(
        ChartPreferenceType.chartsByExerciseCategory(.weightedDuration),
        [ChartPreferenceType.topSetWeight, ChartPreferenceType.totalTimeUnderTension],
      );
    });
  });
}
