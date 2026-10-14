import 'package:heart_models/heart_models.dart';
import 'package:test/test.dart';

void main() {
  const fiveThreeOne = {
    'kind': 'shareOfMax',
    'waves': [
      [
        {'share': 0.65, 'reps': 5},
        {'share': 0.75, 'reps': 5},
        {'share': 0.85, 'reps': 5, 'amrap': true},
      ],
      [
        {'share': 0.7, 'reps': 3},
        {'share': 0.8, 'reps': 3},
        {'share': 0.9, 'reps': 3, 'amrap': true},
      ],
    ],
    'step': 5,
    'missCut': 0.1,
    'misses': 2,
  };

  group('GrowthRule', () {
    test('every kind round-trips', () {
      for (final json in [
        {'kind': 'none'},
        {'kind': 'addWeight', 'step': 2.5},
        {'kind': 'rangeThenWeight', 'step': 2.5},
        {'kind': 'longer', 'step': 5},
        fiveThreeOne,
      ]) {
        expect(GrowthRule.fromJson(json).toMap(), json);
      }
    });

    test('shareOfMax fills its defaults and cycles its waves by week', () {
      final rule = GrowthRule.fromJson(
        {...fiveThreeOne}
          ..remove('missCut')
          ..remove('misses'),
      ) as ShareOfMax;
      expect(rule.missCut, ShareOfMax.defaultMissCut);
      expect(rule.misses, ShareOfMax.defaultMisses);
      expect(rule.week(1).last.amrap, isTrue);
      expect(rule.week(2).first.share, 0.7);
      expect(rule.week(3).first.share, 0.65, reason: 'week 3 of a two-week wave is its first week again');
    });

    test('rejects an unknown kind and parameters out of range', () {
      for (final json in [
        {'kind': 'percentOfBodyweight'},
        {'kind': 'addWeight'},
        {'kind': 'addWeight', 'step': 0},
        {'kind': 'longer', 'step': -5},
        {...fiveThreeOne, 'waves': []},
        {...fiveThreeOne, 'missCut': 1},
        {...fiveThreeOne, 'misses': 0},
        {
          ...fiveThreeOne,
          'waves': [
            [
              {'share': 0, 'reps': 5},
            ],
          ],
        },
      ]) {
        expect(() => GrowthRule.fromJson(json), throwsArgumentError, reason: '$json');
      }
    });
  });

  group('Program', () {
    test('round-trips the wire shape', () {
      final json = {
        'id': 'p1',
        'name': 'Getting stronger',
        'note': 'three a week, any days',
        'source': 'getting_stronger_1',
        'perWeek': 3,
        'days': [1, 3, 5],
        'weeks': 12,
        'rules': {
          'e1': {'kind': 'addWeight', 'step': 2.5},
          'e2': fiveThreeOne,
        },
        'constraint': 'avoid_high_axial_load',
        'archived': false,
        'sessions': ['t1', 't2'],
        'createdAt': '2026-10-13T12:00:00.000Z',
      };
      final program = Program.fromJson(json);
      expect(program.rules['e1'], const AddWeight(step: 2.5));
      expect(program.days, {1, 3, 5});
      expect(program.toMap(), json);
    });

    test('reads a row of _programs', () {
      final program = Program.fromRow({
        'id': 'p1',
        'name': 'Stretch',
        'per_week': 7,
        'days': [7, 1],
        'rules': '{"e1": {"kind": "longer", "step": 10}}',
        'constraint_key': 'avoid_high_axial_load',
        'archived': false,
        'sessions': ['t1'],
        'created_at': DateTime.utc(2026, 10, 13),
      });
      expect(program.perWeek, 7);
      expect(program.constraint, 'avoid_high_axial_load');
      expect(program.rules['e1'], const Longer(step: 10));
      expect(program.createdAt, DateTime.utc(2026, 10, 13));
      expect(program.toMap()['days'], [1, 7]);
    });

    test('carries a rule this build cannot read, and writes it back', () {
      final program = Program.fromJson({
        'name': 'From the future',
        'rules': {
          'e1': {'kind': 'addWeight', 'step': 2.5},
          'e2': {'kind': 'autoregulated', 'rpe': 8},
        },
      });
      expect(program.rules.keys, ['e1']);
      expect(program.toMap()['rules'], {
        'e2': {'kind': 'autoregulated', 'rpe': 8},
        'e1': {'kind': 'addWeight', 'step': 2.5},
      });
    });

    test('a rule the user sets replaces an unread one for the same exercise', () {
      final program = Program.fromJson({
        'name': 'p',
        'rules': {
          'e2': {'kind': 'autoregulated'},
        },
      }).copyWith(rules: {'e2': const NoGrowth()});
      expect(program.toMap()['rules'], {
        'e2': {'kind': 'none'},
      });
    });

    test('leaves out what is not set', () {
      expect(Program(name: 'Plain').toMap(), {'name': 'Plain', 'rules': {}, 'archived': false, 'sessions': []});
    });
  });

  group('Template', () {
    test('carries its program and note on the wire and the row', () {
      final template = Template.fromJson(const {'id': 't1', 'order': 0, 'programId': 'p1', 'note': 'heavy day'});
      expect(template.programId, 'p1');
      expect(template.note, 'heavy day');
      expect(template.toMap(), containsPair('programId', 'p1'));
      expect(template.copyWith(folder: null).programId, 'p1');

      final row = Template.fromRow(const {'id': 't1', 'program_id': 'p1', 'note': 'heavy day'});
      expect(row.programId, 'p1');
      expect(row.note, 'heavy day');
    });

    test('a plain template writes neither key', () {
      final map = Template.fromJson(const {'id': 't1', 'order': 0}).toMap();
      expect(map.containsKey('programId'), isFalse);
      expect(map.containsKey('note'), isFalse);
    });
  });
}
