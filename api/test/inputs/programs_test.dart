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
      ]) {
        await expectLater(
          ProgramCreateIn.fromRequest(req(body: {'name': 'p', 'rules': rules})),
          badRequest('invalid_rule'),
          reason: '$rules',
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
}
