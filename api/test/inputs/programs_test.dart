import 'package:heart/globals/globals.dart';
import 'package:heart/inputs/inputs.dart';
import 'package:heart/models/errors.dart';
import 'package:heart_models/heart_models.dart';
import 'package:relic_core/relic_core.dart';
import 'package:test/test.dart';

import '../helpers/request.dart';

const _meId = 'u1';
const _bench = '0198c1a2-b3c4-7d5e-8f60-718293a4b501';
const _squat = '0198c1a2-b3c4-7d5e-8f60-718293a4b502';
const _program = '0198c1a2-b3c4-7d5e-8f60-718293a4b510';

Request req({Map<String, dynamic> body = const {}, Map<String, String> query = const {}}) {
  return jsonRequest(body: body, query: query)..user = User(id: _meId);
}

Matcher badRequest([String? code]) {
  final matcher = isA<BadRequest>();
  return throwsA(code == null ? matcher : matcher.having((e) => e.code, 'code', code));
}

void main() {
  group('ProgramCreateIn', () {
    test('reads the program and its sessions', () async {
      final input = await ProgramCreateIn.fromRequest(
        req(
          body: {
            'id': _program,
            'name': '  Getting stronger ',
            'note': 'three a week',
            'source': 'getting_stronger_1',
            'perWeek': 3,
            'days': [1, 3, 5, 3],
            'weeks': 12,
            'rules': {
              _bench: {'kind': 'addWeight', 'step': 2.5},
            },
            'constraint': 'avoid_high_axial_load',
            'sessions': [
              {
                'name': 'A',
                'note': 'heavy',
                'exercises': [
                  {
                    'exercise': _squat,
                    'sets': [
                      {'reps': 5, 'weight': 60},
                    ],
                  },
                ],
              },
            ],
          },
        ),
      );

      final program = input.program;
      expect(program.id, _program);
      expect(program.name, 'Getting stronger');
      expect(program.days, {1, 3, 5});
      expect(program.rules[_bench], const AddWeight(step: 2.5));
      expect(program.constraint, 'avoid_high_axial_load');
      final session = input.sessions.single;
      expect(session.userId, _meId);
      expect(session.name, 'A');
      expect(session.note, 'heavy');
      expect(session.exercises.single.exerciseId, _squat);
    });

    test('a name is all it needs', () async {
      final input = await ProgramCreateIn.fromRequest(req(body: {'name': 'Stretch'}));
      expect(input.program.rules, isEmpty);
      expect(input.sessions, isEmpty);
    });

    test('rejects what the schema would', () async {
      for (final body in [
        <String, dynamic>{},
        {'name': ' '},
        {'name': 'x' * 101},
        {'name': 'p', 'perWeek': 0},
        {'name': 'p', 'perWeek': 29},
        {'name': 'p', 'perWeek': 2.5},
        {'name': 'p', 'weeks': 105},
        {
          'name': 'p',
          'days': [0],
        },
        {
          'name': 'p',
          'days': [8],
        },
        {'name': 'p', 'sessions': {}},
        {
          'name': 'p',
          'sessions': ['A'],
        },
        {
          'name': 'p',
          'sessions': List.filled(51, {'name': 'A'}),
        },
      ]) {
        await expectLater(ProgramCreateIn.fromRequest(req(body: body)), badRequest(), reason: '$body');
      }
    });

    test('content keys are checked for spelling only', () async {
      await expectLater(
        ProgramCreateIn.fromRequest(req(body: {'name': 'p', 'source': 'Getting Stronger'})),
        badRequest('invalid_key'),
      );
      await expectLater(
        ProgramCreateIn.fromRequest(req(body: {'name': 'p', 'constraint': 'x' * 65})),
        badRequest('invalid_key'),
      );
    });

    test('a rule says what a miss does and how the AMRAP set moves it (heart-api#228)', () async {
      final input = await ProgramCreateIn.fromRequest(
        req(
          body: {
            'name': 'p',
            'rules': {
              _bench: {
                'kind': 'addWeight',
                'step': 2.5,
                'miss': {'when': 'totalReps', 'floor': 15, 'after': 1, 'cut': 0.1},
                'amrap': [
                  {'reps': 10, 'step': 5},
                ],
              },
            },
          },
        ),
      );
      final rule = input.program.rules[_bench]!;
      expect(rule.miss?.floor, 15);
      expect(rule.amrap.single.step, 5);
    });

    test('a cut and a hold in the AMRAP table are steps too', () async {
      final input = await ProgramCreateIn.fromRequest(
        req(
          body: {
            'name': 'p',
            'rules': {
              _bench: {
                'kind': 'shareOfMax',
                'step': 5,
                'waves': [
                  [
                    {'share': 0.85, 'reps': 5, 'amrap': true},
                  ],
                ],
                'amrap': [
                  {'reps': 0, 'step': -5},
                  {'reps': 5, 'step': 0},
                  {'reps': 8, 'step': 5},
                ],
              },
            },
          },
        ),
      );
      expect(input.program.rules[_bench]!.amrap.map((row) => row.step), [-5, 0, 5]);
    });

    test('rules are read strictly', () async {
      for (final rules in [
        [],
        {
          'bench': {'kind': 'none'},
        },
        {_bench: 'none'},
        {
          _bench: {'kind': 'autoregulated'},
        },
        {
          _bench: {'kind': 'addWeight', 'step': 0},
        },
        {
          _bench: {'kind': 'shareOfMax', 'step': 5, 'waves': []},
        },
        {
          _bench: {'kind': 'addWeight', 'step': 2.5, 'tempo': '3-1-1'},
        },
        {
          _bench: {
            'kind': 'addWeight',
            'step': 2.5,
            'miss': {'after': 0},
          },
        },
        {
          _bench: {
            'kind': 'addWeight',
            'step': 2.5,
            'miss': {'after': 2, 'grace': 1},
          },
        },
        {
          _bench: {
            'kind': 'addWeight',
            'step': 2.5,
            'miss': {'cut': 1},
          },
        },
        {
          _bench: {
            'kind': 'addWeight',
            'step': 2.5,
            'miss': {'when': 'totalReps', 'floor': 0},
          },
        },
        {
          _bench: {
            'kind': 'addWeight',
            'step': 2.5,
            'amrap': [
              {'reps': 10, 'step': 5, 'per': 'side'},
            ],
          },
        },
        {
          _bench: {
            'kind': 'addWeight',
            'step': 2.5,
            'amrap': [
              {'reps': -1, 'step': 5},
            ],
          },
        },
        {
          _bench: {'kind': 'addWeight', 'step': 2.5, 'amrap': 'double'},
        },
      ]) {
        await expectLater(
          ProgramCreateIn.fromRequest(req(body: {'name': 'p', 'rules': rules})),
          badRequest('invalid_rule'),
          reason: '$rules',
        );
      }
    });
  });

  group('lighter weeks (heart-api#229)', () {
    test('a program schedules one every N cycles', () async {
      final input = await ProgramCreateIn.fromRequest(
        req(
          body: {
            'name': 'p',
            'deload': {'every': 6, 'load': 0.9},
          },
        ),
      );
      expect(input.program.deload, const Deload(every: 6));
    });

    test('a bad one is refused', () async {
      for (final deload in [
        {'every': 1},
        {'every': 4, 'volume': 1.5},
        {'every': 4, 'skip': true},
        'monthly',
      ]) {
        await expectLater(
          ProgramCreateIn.fromRequest(req(body: {'name': 'p', 'deload': deload})),
          badRequest('invalid_deload'),
          reason: '$deload',
        );
      }
    });

    test('an advance names its exercises; nothing else does (heart-api#231)', () async {
      const workout = '0198c1a2-b3c4-7d5e-8f60-718293a4b520';
      final input = await ProgramActionIn.fromRequest(
        req(
          body: {'kind': 'advance', 'from': _bench, 'to': _squat, 'workoutId': workout, 'at': '2026-10-15T08:00:00Z'},
        ),
      );
      expect((input.action.from, input.action.to, input.action.workoutId), (_bench, _squat, workout));
      for (final body in [
        {'kind': 'advance', 'from': _bench, 'at': '2026-10-15T08:00:00Z'},
        {'kind': 'pause', 'from': _bench, 'to': _squat, 'at': '2026-10-15T08:00:00Z'},
        {'kind': 'pause', 'workoutId': workout, 'at': '2026-10-15T08:00:00Z'},
      ]) {
        await expectLater(ProgramActionIn.fromRequest(req(body: body)), badRequest(), reason: '$body');
      }
    });

    test('a ladder rule climbs exercise ids', () async {
      final input = await ProgramCreateIn.fromRequest(
        req(
          body: {
            'name': 'p',
            'rules': {
              _bench: {
                'kind': 'ladder',
                'rungs': [_bench, _squat],
                'top': 12,
                'bottom': 8,
              },
            },
          },
        ),
      );
      expect(input.program.rules[_bench], isA<Ladder>());
      await expectLater(
        ProgramCreateIn.fromRequest(
          req(
            body: {
              'name': 'p',
              'rules': {
                _bench: {
                  'kind': 'ladder',
                  'rungs': ['push-up', 'decline-push-up'],
                  'top': 12,
                  'bottom': 8,
                },
              },
            },
          ),
        ),
        badRequest('invalid_rule'),
      );
    });

    test('a lighter week is an action', () async {
      final input = await ProgramActionIn.fromRequest(req(body: {'kind': 'lighter', 'at': '2026-10-15T08:00:00Z'}));
      expect(input.action.kind, ProgramActionKind.lighter);
    });
  });

  group('phases and tests (heart-api#233)', () {
    const a = '0198c1a2-b3c4-7d5e-8f60-718293a4b530';
    const b = '0198c1a2-b3c4-7d5e-8f60-718293a4b531';

    test('a program runs in phases and names its tests', () async {
      final input = await ProgramCreateIn.fromRequest(
        req(
          body: {
            'name': 'p',
            'phases': [
              {
                'name': 'Volume',
                'sessions': [a],
                'cycles': 2,
              },
              {
                'sessions': [b],
              },
            ],
            'tests': {
              b: {'share': 0.9},
            },
          },
        ),
      );
      expect(input.program.phases.map((phase) => phase.cycles), [2, null]);
      expect(input.program.tests[b]?.share, 0.9);
    });

    test('a phase that runs on must be last, and every phase is checked', () async {
      for (final phases in [
        [
          {
            'sessions': [a],
          },
          {
            'sessions': [b],
            'cycles': 2,
          },
        ],
        [
          {'sessions': <String>[]},
        ],
        [
          {
            'sessions': ['day-a'],
          },
        ],
        [
          {
            'sessions': [a],
            'cycles': 0,
          },
        ],
      ]) {
        await expectLater(
          ProgramCreateIn.fromRequest(req(body: {'name': 'p', 'phases': phases})),
          badRequest('invalid_phase'),
          reason: '$phases',
        );
      }
    });

    test('a test is keyed by a session id, with a share up to 1', () async {
      for (final tests in [
        {
          'day-a': {'share': 0.9},
        },
        {
          a: {'share': 1.2},
        },
        {a: 0.9},
      ]) {
        await expectLater(
          ProgramCreateIn.fromRequest(req(body: {'name': 'p', 'tests': tests})),
          badRequest('invalid_test'),
          reason: '$tests',
        );
      }
    });
  });

  group('ProgramUpdateIn', () {
    test('a full replace: what is left out is cleared, source is never read', () async {
      final input = await ProgramUpdateIn.fromRequest(
        req(body: {'name': 'Renamed', 'source': 'ignored', 'archived': true}),
      );
      expect(input.program.name, 'Renamed');
      expect(input.program.source, isNull);
      expect(input.program.perWeek, isNull);
      expect(input.program.archived, isTrue);
    });
  });

  group('ProgramDeleteQuery', () {
    test('keeps the templates only when asked', () {
      expect(ProgramDeleteQuery.fromRequest(req()).keepTemplates, isFalse);
      expect(ProgramDeleteQuery.fromRequest(req(query: {'keepTemplates': 'true'})).keepTemplates, isTrue);
    });
  });

  group('ProgramActionIn', () {
    test('a replay names its week; nothing else does', () async {
      final replay = await ProgramActionIn.fromRequest(
        req(body: {'kind': 'replay', 'week': 2, 'at': '2026-10-14T18:00:00Z'}),
      );
      expect(replay.action.week, 2);
      final pause = await ProgramActionIn.fromRequest(req(body: {'kind': 'pause', 'at': '2026-10-14T18:00:00Z'}));
      expect(pause.action.kind, ProgramActionKind.pause);

      for (final body in [
        {'kind': 'replay', 'at': '2026-10-14T18:00:00Z'},
        {'kind': 'replay', 'week': 0, 'at': '2026-10-14T18:00:00Z'},
        {'kind': 'pause', 'week': 2, 'at': '2026-10-14T18:00:00Z'},
        {'kind': 'deload', 'at': '2026-10-14T18:00:00Z'},
        {'kind': 'pause'},
      ]) {
        await expectLater(ProgramActionIn.fromRequest(req(body: body)), badRequest(), reason: '$body');
      }
    });
  });

  group('ProgramBaseIn', () {
    const workout = '0198c1a2-b3c4-7d5e-8f60-718293a4b520';
    const action = '0198c1a2-b3c4-7d5e-8f60-718293a4b521';

    test('a base may belong to one occurrence of a lift', () async {
      const slot = '0198c1a2-b3c4-7d5e-8f60-718293a4b522';
      final input = await ProgramBaseIn.fromRequest(
        req(body: {'exerciseId': _bench, 'slot': slot, 'value': 80, 'at': '2026-10-14T18:00:00Z'}),
      );
      expect(input.base.slot, slot);
      await expectLater(
        ProgramBaseIn.fromRequest(
          req(body: {'exerciseId': _bench, 'slot': 'monday', 'value': 80, 'at': '2026-10-14T18:00:00Z'}),
        ),
        badRequest(),
      );
    });

    test('reads a bump caused by a workout', () async {
      final input = await ProgramBaseIn.fromRequest(
        req(body: {'exerciseId': _bench, 'value': 102.5, 'workoutId': workout, 'at': '2026-10-14T18:00:00Z'}),
      );
      expect(input.base.value, 102.5);
      expect(input.base.workoutId, workout);
      expect(input.base.isManual, isFalse);
    });

    test('rejects a missing exercise, a value of zero, and two causes', () async {
      for (final body in [
        {'value': 100, 'at': '2026-10-14T18:00:00Z'},
        {'exerciseId': _bench, 'value': 0, 'at': '2026-10-14T18:00:00Z'},
        {'exerciseId': _bench, 'value': 100, 'workoutId': workout, 'actionId': action, 'at': '2026-10-14T18:00:00Z'},
        {'exerciseId': _bench, 'value': 100},
      ]) {
        await expectLater(ProgramBaseIn.fromRequest(req(body: body)), badRequest(), reason: '$body');
      }
    });
  });
}
