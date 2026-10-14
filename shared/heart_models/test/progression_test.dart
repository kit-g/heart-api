import 'package:heart_models/heart_models.dart';
import 'package:test/test.dart';

final _bench = Exercise.fromJson({
  'id': '018f2c9a-0000-7000-8000-000000000001',
  'name': 'Bench Press',
  'category': 'Barbell',
  'target': 'Chest',
});

final _plank = Exercise.fromJson({
  'id': '018f2c9a-0000-7000-8000-000000000002',
  'name': 'Plank',
  'category': 'Duration',
  'target': 'Core',
});

/// A ticked working set of [reps] aiming at [target].
ExerciseSet _set(int reps, {SetTarget? target, double weight = 100, SetType type = SetType.normal, bool done = true}) {
  return ExerciseSet(_bench, reps: reps, weight: weight, target: target, setType: type)..isCompleted = done;
}

SetTarget _reps(num min, [num? max, bool amrap = false]) =>
    SetTarget({TargetMeasure.reps: TargetRange(min: min, max: max, amrap: amrap)});

void main() {
  group('Progression.next', () {
    group('add weight', () {
      const rule = AddWeight(step: 2.5);
      final target = _reps(5, 5);

      test('every set made: the base grows by the step', () {
        expect(
          Progression.next(
            rule: rule,
            base: 100,
            sets: [
              _set(5, target: target),
              _set(5, target: target),
            ],
          ),
          const Grow(102.5),
        );
      });

      test('a set short is a miss; the third in a row cuts 10%, down to the step', () {
        final sets = [_set(5, target: target), _set(3, target: target)];
        expect(Progression.next(rule: rule, base: 100, sets: sets), const Missed(1));
        expect(Progression.next(rule: rule, base: 100, sets: sets, misses: 1), const Missed(2));
        expect(Progression.next(rule: rule, base: 100, sets: sets, misses: 2), const Cut(90));
        expect(
          Progression.next(rule: rule, base: 102.5, sets: sets, misses: 2),
          const Cut(90),
          reason: '92.25 down to 2.5 kg',
        );
      });

      test('warm-ups, unticked and supplemental sets are not judged', () {
        final sets = [
          _set(2, target: target, type: SetType.warmup),
          _set(1, target: target, done: false),
          _set(1, target: SetTarget({TargetMeasure.reps: const TargetRange(min: 5, max: 5)}, supplemental: true)),
          _set(5, target: target),
        ];
        expect(Progression.next(rule: rule, base: 100, sets: sets), const Grow(102.5));
      });

      test('a lighter week, or no base yet, moves nothing', () {
        final sets = [_set(5, target: target)];
        expect(Progression.next(rule: rule, base: 100, sets: sets, lighter: true), const Hold());
        expect(Progression.next(rule: rule, base: null, sets: sets), const Hold());
        expect(Progression.next(rule: rule, base: 100, sets: const []), const Hold());
      });

      test('the AMRAP table: double the step past 10, the rule\'s step below', () {
        const doubling = AddWeight(step: 2.5, amrap: [AmrapStep(reps: 10, step: 5)]);
        final sets = [_set(5, target: target), _set(5, target: target)];
        List<ExerciseSet> last(int reps) => [...sets, _set(reps, target: _reps(5))];
        expect(Progression.next(rule: doubling, base: 100, sets: last(12)), const Grow(105));
        expect(Progression.next(rule: doubling, base: 100, sets: last(7)), const Grow(102.5));
      });

      test('a total-reps miss, as the r/Fitness beginner routine counts it', () {
        const totals = AddWeight(step: 2.5, miss: MissRule(when: MissWhen.totalReps, floor: 15, after: 1));
        final sets = [_set(5, target: target), _set(5, target: target), _set(4, target: _reps(5))];
        expect(Progression.next(rule: totals, base: 100, sets: sets), const Cut(90));
      });
    });

    group('range, then weight', () {
      const rule = RangeThenWeight(step: 2.5);
      final range = _reps(8, 12);

      test('every set at the top of its range: the weight goes up', () {
        expect(
          Progression.next(
            rule: rule,
            base: 60,
            sets: [
              _set(12, target: range),
              _set(12, target: range),
            ],
          ),
          const Grow(62.5),
        );
      });

      test('inside the range: hold; below it: a miss', () {
        expect(
          Progression.next(
            rule: rule,
            base: 60,
            sets: [
              _set(12, target: range),
              _set(10, target: range),
            ],
          ),
          const Hold(),
        );
        expect(
          Progression.next(
            rule: rule,
            base: 60,
            sets: [
              _set(12, target: range),
              _set(6, target: range),
            ],
          ),
          const Missed(1),
        );
      });
    });

    group('share of a max', () {
      final rule = GrowthRule.fromJson(const {
        'kind': 'shareOfMax',
        'step': 5,
        'waves': [
          [
            {'share': 0.65, 'reps': 5},
            {'share': 0.85, 'reps': 5, 'amrap': true},
          ],
          [
            {'share': 0.4, 'reps': 5},
          ],
        ],
      });
      List<ExerciseSet> session(int amrap) => [_set(5, target: _reps(5, 5)), _set(amrap, target: _reps(5))];

      test('the max moves only at the end of a wave', () {
        expect(Progression.next(rule: rule, base: 100, sets: session(7), week: 1), const Hold());
        expect(Progression.next(rule: rule, base: 100, sets: session(7), week: 2), const Grow(105));
        expect(Progression.next(rule: rule, base: 100, sets: session(7), week: 2, closesCycle: false), const Hold());
      });

      test('an AMRAP short is a miss; two in a row cut the max 10%', () {
        expect(Progression.next(rule: rule, base: 100, sets: session(3), week: 1), const Missed(1));
        expect(Progression.next(rule: rule, base: 100, sets: session(3), week: 1, misses: 1), const Cut(90));
      });
    });

    test('longer: a cycle with every hold at the base adds the step', () {
      const rule = Longer(step: 5);
      final hold = ExerciseSet(_plank, duration: 30)..isCompleted = true;
      expect(Progression.next(rule: rule, base: 30, sets: [hold]), const Grow(35));
      expect(Progression.next(rule: rule, base: 30, sets: [hold], closesCycle: false), const Hold());
      expect(Progression.next(rule: rule, base: 40, sets: [hold]), const Hold());
    });

    test('longer: a run grows by the measure its target names, not by its time', () {
      const rule = Longer(step: 1);
      final run = Exercise.fromJson({
        'id': '018f2c9a-0000-7000-8000-000000000003',
        'name': 'Running',
        'category': 'Cardio',
        'target': 'Cardio',
      });
      final km = SetTarget({TargetMeasure.distance: const TargetRange(min: 5)});
      final short = ExerciseSet(run, duration: 1500, distance: 3, target: km)..isCompleted = true;
      final far = ExerciseSet(run, distance: 5, target: km)..isCompleted = true;
      expect(Progression.next(rule: rule, base: 5, sets: [short]), const Hold());
      expect(Progression.next(rule: rule, base: 5, sets: [far]), const Grow(6));
    });

    test('as written: nothing moves', () {
      expect(Progression.next(rule: const NoGrowth(), base: 100, sets: [_set(5)]), const Hold());
    });
  });

  group('Progression.streak', () {
    test('misses in a row at the end, a made session resetting it', () {
      const rule = AddWeight(step: 2.5);
      final target = _reps(5, 5);
      final made = [_set(5, target: target)];
      final missed = [_set(3, target: target)];
      expect(Progression.streak(rule, [missed, made, missed, missed]), 2);
      expect(Progression.streak(rule, [missed, made]), 0);
      expect(Progression.streak(const NoGrowth(), [missed]), 0);
    });

    test('a lighter week neither misses nor breaks a streak', () {
      const rule = AddWeight(step: 2.5);
      final target = _reps(5, 5);
      final made = [_set(5, target: target)];
      final missed = [_set(3, target: target)];
      expect(Progression.streak(rule, [made, missed], lighter: [false, true]), 0);
      expect(Progression.streak(rule, [missed, made, missed], lighter: [false, true]), 2);
    });
  });

  group('Progression.test', () {
    test('a share of the best estimated max, from sets of 10 or fewer, down to the step', () {
      final sets = [
        _set(5, weight: 100),
        _set(12, weight: 90),
        _set(3, weight: 105),
      ];
      // Brzycki: 100 × 5 → 112.5; 105 × 3 → 111.1; the 12-rep set doesn't count
      expect(Progression.test(sets), 100);
      expect(Progression.test([_set(12, weight: 90)]), isNull);
    });
  });

  group('rules', () {
    test('miss and amrap round-trip; a field this build doesn\'t know is kept', () {
      final json = {
        'kind': 'rangeThenWeight',
        'step': 2.5,
        'miss': {'when': 'anySet', 'after': 3, 'cut': 0.1},
        'amrap': [
          {'reps': 10, 'step': 5},
        ],
        'tempo': '3-1-1',
      };
      final rule = GrowthRule.fromJson(json);
      expect(rule.miss?.after, 3);
      expect(rule.extra, {'tempo': '3-1-1'});
      expect(rule.toMap(), json);
    });

    test('share of a max reads its old fields as its miss rule', () {
      final rule = GrowthRule.fromJson(const {
        'kind': 'shareOfMax',
        'step': 5,
        'misses': 2,
        'missCut': 0.1,
        'waves': [
          [
            {'share': 0.85, 'reps': 5, 'amrap': true},
          ],
        ],
      });
      expect(rule.miss?.when, MissWhen.amrap);
      expect(rule.miss?.after, 2);
    });

    test('a bad miss or amrap table is refused', () {
      for (final json in [
        {
          'kind': 'addWeight',
          'step': 2.5,
          'miss': {'when': 'sometimes'},
        },
        {
          'kind': 'addWeight',
          'step': 2.5,
          'miss': {'cut': 1},
        },
        {'kind': 'addWeight', 'step': 2.5, 'amrap': 'double'},
      ]) {
        expect(() => GrowthRule.fromJson(json), throwsArgumentError, reason: '$json');
      }
    });
  });
}
