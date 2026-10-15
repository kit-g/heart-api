import 'package:heart_models/heart_models.dart';
import 'package:test/test.dart';

final _squat = Exercise.fromJson({
  'id': '018f2c9a-0000-7000-8000-000000000001',
  'name': 'Squat',
  'category': 'Barbell',
  'target': 'Legs',
});

const _t1 = Stages(
  step: 2.5,
  stages: [
    Stage(sets: 5, reps: 3, amrap: true),
    Stage(sets: 6, reps: 2, amrap: true),
    Stage(sets: 10, reps: 1, amrap: true),
  ],
);

/// A ticked working set of [reps] aiming at [aim] reps.
ExerciseSet _set(int reps, int aim) {
  return ExerciseSet(
    _squat,
    reps: reps,
    weight: 100,
    target: SetTarget({TargetMeasure.reps: TargetRange.exactly(aim)}),
  )..isCompleted = true;
}

void main() {
  group('stages (heart-api#256)', () {
    group('the rule', () {
      test('round-trips, and defaults to moving on the first miss', () {
        final json = {
          'kind': 'stages',
          'stages': [
            {'sets': 3, 'reps': 10},
            {'sets': 3, 'reps': 8},
            {'sets': 3, 'reps': 6, 'amrap': true},
          ],
          'step': 2.5,
        };
        final rule = GrowthRule.fromJson(json) as Stages;
        expect(rule.stages, const [
          Stage(sets: 3, reps: 10),
          Stage(sets: 3, reps: 8),
          Stage(sets: 3, reps: 6, amrap: true),
        ]);
        expect(rule.miss.after, 1);
        expect(rule.miss.cut, MissRule.defaultCut);
        expect(rule.toMap(), json);
        expect(rule.stage(7), const Stage(sets: 3, reps: 6, amrap: true), reason: 'past the list is the last stage');
      });

      test('a miss rule that says only its cut still moves on the first miss', () {
        final rule = GrowthRule.fromJson({
          'kind': 'stages',
          'step': 2.5,
          'stages': [
            {'sets': 5, 'reps': 3},
            {'sets': 6, 'reps': 2},
          ],
          'miss': {'cut': 0.15},
        }) as Stages;
        expect((rule.miss.after, rule.miss.cut), (1, 0.15));
        final waiting = GrowthRule.fromJson({
          ...rule.toMap(),
          'miss': {'after': 2},
        }) as Stages;
        expect(waiting.miss.after, 2, reason: 'a run the rule asks for stands');
      });

      test('refuses fewer than two stages, or a stage out of range', () {
        Map<String, dynamic> stages(List<Object?> list) => {'kind': 'stages', 'step': 2.5, 'stages': list};
        expect(
          () => GrowthRule.fromJson(
            stages([
              {'sets': 5, 'reps': 3},
            ]),
          ),
          throwsArgumentError,
        );
        expect(
          () => GrowthRule.fromJson(
            stages([
              {'sets': 0, 'reps': 3},
              {'sets': 5, 'reps': 3},
            ]),
          ),
          throwsArgumentError,
        );
        expect(
          () => GrowthRule.fromJson(
            stages([
              {'sets': 5, 'reps': 3, 'amrap': 'yes'},
              {'sets': 5, 'reps': 3},
            ]),
          ),
          throwsArgumentError,
        );
        expect(() => GrowthRule.fromJson({'kind': 'stages', 'stages': []}), throwsArgumentError);
      });

      test('a program carries a stages rule an older reading would not know', () {
        final program = Program.fromJson({
          'name': 'Tiers',
          'sessions': [],
          'rules': {_squat.id: _t1.toMap()},
        });
        expect(program.rules[_squat.id], _t1);
      });
    });

    group('Progression.next', () {
      final made = [for (var i = 0; i < 4; i++) _set(3, 3), _set(6, 3)];
      final short = [_set(3, 3), _set(3, 3), _set(2, 3)];

      test('a session that makes its targets grows the base, on any stage', () {
        expect(Progression.next(rule: _t1, base: 100, sets: made), const Grow(102.5));
        expect(Progression.next(rule: _t1, base: 100, sets: made, stage: 2), const Grow(102.5));
      });

      test('a miss moves to the next stage at the same base', () {
        expect(Progression.next(rule: _t1, base: 100, sets: short), const ToStage(1));
        expect(Progression.next(rule: _t1, base: 100, sets: short, stage: 1), const ToStage(2));
      });

      test('a miss on the last stage cuts the base, down to the step, and starts over', () {
        expect(
          Progression.next(rule: _t1, base: 102.5, sets: short, stage: 2),
          const ToStage(0, base: 90),
          reason: '92.25 down to 2.5 kg',
        );
      });

      test('a rule that waits for a run of misses counts them first', () {
        const patient = Stages(
          step: 5,
          miss: MissRule(after: 2, cut: 0.15),
          stages: [Stage(sets: 3, reps: 10), Stage(sets: 3, reps: 8)],
        );
        expect(Progression.next(rule: patient, base: 60, sets: short), const Missed(1));
        expect(Progression.next(rule: patient, base: 60, sets: short, misses: 1), const ToStage(1));
        expect(Progression.next(rule: patient, base: 60, sets: short, misses: 1, stage: 1), const ToStage(0, base: 50));
      });

      test('a lighter week moves nothing', () {
        expect(Progression.next(rule: _t1, base: 100, sets: short, lighter: true), const Hold());
      });

      test('without a base yet a miss still moves the stage; only growing and cutting need one', () {
        expect(Progression.next(rule: _t1, base: null, sets: short), const ToStage(1));
        expect(Progression.next(rule: _t1, base: null, sets: short, stage: 2), const ToStage(0));
        expect(Progression.next(rule: _t1, base: null, sets: made), const Hold());
      });
    });

    group('the stage action', () {
      test('round-trips with its exercise, slot, stage and cause', () {
        final json = {
          'id': '019a0000-0000-7000-8000-000000000001',
          'kind': 'stage',
          'exercise': _squat.id,
          'slot': '019a0000-0000-7000-8000-0000000000b1',
          'stage': 2,
          'workoutId': '019a0000-0000-7000-8000-0000000000c1',
          'at': '2026-10-02T00:00:00.000Z',
        };
        final action = ProgramAction.fromJson(json);
        expect(action.kind, ProgramActionKind.stage);
        expect(action.stage, 2);
        expect(action.toMap(), json);
        final row = ProgramAction.fromRow({
          'kind': 'stage',
          'exercise_id': _squat.id,
          'slot': null,
          'stage': 1,
          'workout_id': null,
          'at': DateTime.utc(2026, 10, 2),
        });
        expect((row.exercise, row.slot, row.stage), (_squat.id, null, 1));
      });

      test('currentStages: the latest per slot, else per exercise', () {
        ProgramAction stage(int to, int day, {String? slot}) => ProgramAction(
          kind: .stage,
          exercise: _squat.id,
          slot: slot,
          stage: to,
          at: DateTime.utc(2026, 10, day),
        );
        expect(
          currentStages([
            stage(1, 2),
            stage(2, 5),
            stage(0, 3),
            stage(1, 4, slot: 'thursday'),
            ProgramAction(kind: .pause, at: DateTime.utc(2026, 10, 6)),
          ]),
          {_squat.id: 2, 'thursday': 1},
        );
      });
    });

    group('rules per slot', () {
      test('atSlot: a slot\'s own entry, else the exercise\'s, never that when the slot has its own rule', () {
        final program = Program(name: 'Tiers', rules: {_squat.id: _t1, 'thursday': _t1});
        final bases = {_squat.id: 140, 'monday-light': 100};
        expect(program.atSlot(bases, _squat.id), 140);
        expect(program.atSlot(bases, _squat.id, slot: 'monday-light'), 100);
        expect(program.atSlot(bases, _squat.id, slot: 'friday'), 140, reason: 'no rule of its own: the lift\'s');
        expect(program.atSlot(bases, _squat.id, slot: 'thursday'), isNull, reason: 'its own rule keeps its own');
      });

      test('a slot\'s own rule comes before its exercise\'s', () {
        final program = Program(
          name: 'Tiers',
          rules: {_squat.id: _t1, 'thursday': const AddWeight(step: 5)},
        );
        expect(program.ruleFor(_squat.id), _t1);
        expect(program.ruleFor(_squat.id, slot: 'monday'), _t1);
        expect(program.ruleFor(_squat.id, slot: 'thursday'), const AddWeight(step: 5));
        expect(program.ruleFor('another'), isNull);
      });
    });
  });
}
