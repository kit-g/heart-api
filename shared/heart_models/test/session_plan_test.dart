import 'package:heart_models/heart_models.dart';
import 'package:test/test.dart';

const _squat = '019a0000-0000-7000-8000-000000000001';
const _front = '019a0000-0000-7000-8000-000000000002';
const _curl = '019a0000-0000-7000-8000-000000000003';
const _plank = '019a0000-0000-7000-8000-000000000004';
const _session = '019a0000-0000-7000-8000-0000000000a1';

Map<String, dynamic> _exercise(String id, String name, {String category = 'Barbell'}) {
  return {'id': id, 'name': name, 'category': category, 'target': 'Legs'};
}

Map<String, dynamic> _set(int index, Map<String, dynamic> target, {String type = 'normal', num? weight}) {
  return {
    'id': '019a0000-0000-7000-8000-00000000${index.toString().padLeft(4, '0')}',
    'completed': false,
    'started_at': '2026-10-01T08:00:00.000Z',
    'set_type': type,
    'weight': ?weight,
    'target': target,
  };
}

Map<String, dynamic> _reps(num min, [num? max]) => {
  'reps': {'min': min, 'max': ?max},
};

/// A template with one slot per entry of [slots]: (slot id, exercise, sets).
Template _template(List<(String, Map<String, dynamic>, List<Map<String, dynamic>>)> slots) {
  return Template.fromJson({
    'id': _session,
    'order': 0,
    'exercises': [
      for (final (index, (slot, exercise, sets)) in slots.indexed)
        {'id': slot, 'exercise': exercise, 'order': index, 'start': '2026-10-01T08:00:00.000Z', 'sets': sets},
    ],
  });
}

ProgramBase _base(String exerciseId, num value, {String? slot, int day = 1}) {
  return ProgramBase(exerciseId: exerciseId, slot: slot, value: value, at: DateTime.utc(2026, 10, day));
}

ProgramPosition _at(Program program, {int week = 1, bool lighter = false}) {
  return ProgramPosition.of(
    program,
    marks: const [],
    actions: [
      if (week > 1) ProgramAction(kind: .replay, week: week, at: DateTime.utc(2026, 10, 2)),
      if (lighter) ProgramAction(kind: .lighter, at: DateTime.utc(2026, 10, 3)),
    ],
    now: DateTime.utc(2026, 10, 5),
  );
}

PlannedSession _plan(Program program, Template session, List<ProgramBase> bases, {int week = 1, bool lighter = false}) {
  return PlannedSession.of(
    program,
    session,
    position: _at(program, week: week, lighter: lighter),
    bases: currentBases(bases),
  );
}

void main() {
  group('PlannedSession.of (heart-api#260)', () {
    const waves = ShareOfMax(
      step: 5,
      waves: [
        [WaveSet(share: 0.65, reps: 5), WaveSet(share: 0.85, reps: 5, amrap: true)],
        [WaveSet(share: 0.7, reps: 3), WaveSet(share: 0.9, reps: 3, amrap: true)],
      ],
    );
    final squatDay = _template([
      (
        '019a0000-0000-7000-8000-0000000000b1',
        _exercise(_squat, 'Squat'),
        [
          _set(1, _reps(5), type: 'warmup', weight: 40),
          _set(2, {..._reps(5, 5), 'share': 0.6}),
          _set(3, {..._reps(5, 5), 'share': 0.6}),
          _set(4, {..._reps(5, 5), 'share': 0.5, 'supplemental': true}),
        ],
      ),
    ]);

    test('a wave sets the week\'s shares and reps in order; weights round down to the step', () {
      final program = Program(name: 'Waves', sessions: const [_session], rules: {_squat: waves});
      final plan = _plan(program, squatDay, [_base(_squat, 140)]);
      expect(plan.week, 1);
      expect(plan.lighter, isFalse);
      final [squat] = plan.exercises;
      expect(squat.base, 140);
      final [warmup, first, top, supplemental] = squat.sets;
      expect(warmup.setType, SetType.warmup);
      expect(warmup.weight, 40, reason: 'a warm-up keeps what it stores');
      expect(first.weight, 90, reason: '65% of 140 is 91, down to 5 kg');
      expect(first.target?[.reps], TargetRange.exactly(5));
      expect(top.weight, 115, reason: '85% of 140 is 119');
      expect(top.target?[.reps], const TargetRange(min: 5));
      expect(supplemental.weight, 70, reason: 'past the wave, the set keeps its own share');
      expect(supplemental.target?.supplemental, isTrue);

      final week2 = _plan(program, squatDay, [_base(_squat, 140)], week: 2);
      expect(week2.week, 2);
      expect([for (final set in week2.exercises.single.sets.skip(1)) set.weight], [95, 125, 70]);
      expect(week2.exercises.single.sets[2].target?[.reps], const TargetRange(min: 3));
    });

    test('the latest base counts; a slot\'s own base comes before the exercise\'s', () {
      final program = Program(name: 'Waves', sessions: const [_session], rules: {_squat: waves});
      final bases = [_base(_squat, 100), _base(_squat, 140, day: 2)];
      expect(_plan(program, squatDay, bases).exercises.single.sets[1].weight, 90);
      final slotted = [...bases, _base(_squat, 120, slot: '019a0000-0000-7000-8000-0000000000b1')];
      final plan = _plan(program, squatDay, slotted);
      expect(plan.exercises.single.base, 120);
      expect(plan.exercises.single.sets[1].weight, 75, reason: '65% of 120 is 78');
    });

    test('a share of another lift weighs that lift\'s base, at its step', () {
      final session = _template([
        (
          '019a0000-0000-7000-8000-0000000000b2',
          _exercise(_front, 'Front Squat'),
          [
            _set(1, {..._reps(5, 5), 'share': 0.55, 'of': _squat}),
          ],
        ),
      ]);
      final program = Program(name: 'Waves', sessions: const [_session], rules: {_squat: waves});
      final plan = _plan(program, session, [_base(_squat, 140)]);
      expect(plan.exercises.single.base, isNull);
      expect(plan.exercises.single.sets.single.weight, 75, reason: '55% of 140 is 77, down to 5 kg');
    });

    test('a lift without a base keeps the template\'s weights; a share alone weighs nothing', () {
      final program = Program(name: 'Waves', sessions: const [_session], rules: {_squat: waves});
      final plan = _plan(program, squatDay, const []);
      expect([for (final set in plan.exercises.single.sets) set.weight], [40, null, null, null]);
    });

    test('add weight: the base is the working weight; a lighter week cuts load and sets', () {
      final session = _template([
        (
          '019a0000-0000-7000-8000-0000000000b3',
          _exercise(_curl, 'Curl'),
          [
            _set(1, _reps(8, 12), type: 'warmup', weight: 10),
            for (var i = 2; i <= 4; i++) _set(i, _reps(8, 12), weight: 20),
          ],
        ),
      ]);
      final program = Program(
        name: 'Arms',
        sessions: const [_session],
        rules: {_curl: const RangeThenWeight(step: 2.5)},
        deload: const Deload(every: 4, load: 0.8, volume: 0.5),
      );
      final normal = _plan(program, session, [_base(_curl, 30)]);
      expect([for (final set in normal.exercises.single.sets) set.weight], [10, 30, 30, 30]);

      final light = _plan(program, session, [_base(_curl, 30)], lighter: true);
      expect(light.lighter, isTrue);
      expect(
        [for (final set in light.exercises.single.sets) set.weight],
        [10, 22.5, 22.5],
        reason: 'warm-ups stay; half of three working sets is two; 80% of 30 is 24, down to 2.5 kg',
      );

      final scheduled = _plan(program, session, [_base(_curl, 30)], week: 4);
      expect(scheduled.lighter, isTrue, reason: 'deload every 4 weeks');
    });

    test('a lighter cycle without a deload uses the defaults', () {
      final session = _template([
        (
          '019a0000-0000-7000-8000-0000000000b3',
          _exercise(_curl, 'Curl'),
          [
            for (var i = 1; i <= 4; i++) _set(i, _reps(8, 12)),
          ],
        ),
      ]);
      final program = Program(name: 'Arms', sessions: const [_session], rules: {_curl: const AddWeight(step: 2.5)});
      final light = _plan(program, session, [_base(_curl, 30)], lighter: true);
      expect(
        [for (final set in light.exercises.single.sets) set.weight],
        [25, 25],
        reason: '90% of 30 is 27, down to 2.5 kg',
      );
    });

    test('a test session plans no weights and says its share', () {
      final program = Program(
        name: 'Waves',
        sessions: const [_session],
        rules: {_squat: waves},
        tests: {_session: const ProgramTest(share: 0.9)},
      );
      final plan = _plan(program, squatDay, [_base(_squat, 140)]);
      expect(plan.test, 0.9);
      expect([for (final set in plan.exercises.single.sets) set.weight], [40, null, null, null]);
      expect(plan.exercises.single.sets[1].target?.share, 0.6, reason: 'a test runs no wave');
      expect(plan.toMap()['test'], 0.9);
    });

    test('longer: the base is the measure the target names', () {
      final session = _template([
        (
          '019a0000-0000-7000-8000-0000000000b4',
          _exercise(_plank, 'Plank', category: 'Duration'),
          [
            _set(1, {
              'duration': {'min': 30},
            }),
          ],
        ),
      ]);
      final program = Program(name: 'Core', sessions: const [_session], rules: {_plank: const Longer(step: 5)});
      final plan = _plan(program, session, [_base(_plank, 45)]);
      expect(plan.exercises.single.sets.single.duration, 45);
      expect(plan.exercises.single.sets.single.weight, isNull);
    });

    test('a test session plans no weight even where the template stores one; warm-ups keep theirs', () {
      final stored = _template([
        (
          '019a0000-0000-7000-8000-0000000000b1',
          _exercise(_squat, 'Squat'),
          [
            _set(1, _reps(5), type: 'warmup', weight: 40),
            _set(2, _reps(3, 5), weight: 100),
          ],
        ),
      ]);
      final program = Program(
        name: 'Waves',
        sessions: const [_session],
        rules: {_squat: const AddWeight(step: 2.5)},
        tests: {_session: const ProgramTest()},
      );
      final plan = _plan(program, stored, [_base(_squat, 140)]);
      expect([for (final set in plan.exercises.single.sets) set.weight], [40, null]);
    });

    test('a set\'s stored reps stand only where its target names none', () {
      final session = _template([
        (
          '019a0000-0000-7000-8000-0000000000b1',
          _exercise(_squat, 'Squat'),
          [
            {
              ..._set(1, {'share': 0.6}),
              'reps': 8,
            },
            {..._set(2, _reps(5, 5)), 'reps': 8},
          ],
        ),
      ]);
      const wave = ShareOfMax(
        step: 5,
        waves: [
          [WaveSet(share: 0.7, reps: 3), WaveSet(share: 0.8, reps: 3)],
        ],
      );
      final plan = _plan(Program(name: 'Waves', sessions: const [_session], rules: {_squat: wave}), session, [
        _base(_squat, 100),
      ]);
      expect([for (final set in plan.exercises.single.sets) set.reps], [null, null], reason: 'the wave sets the reps');
      final plain = _plan(Program(name: 'Plain', sessions: const [_session]), session, const []);
      expect([for (final set in plain.exercises.single.sets) set.reps], [8, null]);
    });

    test('on the wire', () {
      final program = Program(name: 'Waves', sessions: const [_session], rules: {_squat: waves});
      final map = _plan(program, squatDay, [_base(_squat, 140)]).toMap();
      expect(map['templateId'], _session);
      expect(map['week'], 1);
      expect(map['lighter'], false);
      expect(map, isNot(contains('test')));
      final [exercise as Map] = map['exercises'] as List;
      expect(exercise['slot'], '019a0000-0000-7000-8000-0000000000b1');
      expect(exercise['exerciseId'], _squat);
      expect(exercise['base'], 140);
      final sets = exercise['sets'] as List;
      expect(sets.first, {
        'setType': 'warmup',
        'target': {
          'reps': {'min': 5},
        },
        'weight': 40,
      });
      expect(sets[2], {
        'target': {
          'reps': {'min': 5},
          'share': 0.85,
        },
        'weight': 115,
      });
    });
  });
}
