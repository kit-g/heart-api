import 'package:heart/models/program_copy.dart';
import 'package:heart_models/heart_models.dart';
import 'package:test/test.dart';

void main() {
  const session = '01900000-0000-7000-8000-000000000001';
  const slot = '01900000-0000-7000-8000-000000000002';
  const exercise = '01900000-0000-7000-8000-000000000003';
  const other = '01900000-0000-7000-8000-000000000004';

  // the places a body holds an id today
  final body = <String, dynamic>{
    'name': 'Five three one',
    'rules': {
      exercise: {
        'kind': 'ladder',
        'rungs': [exercise, other],
      },
      slot: {'kind': 'addWeight', 'step': 2.5},
    },
    'tests': {
      exercise: {'share': 0.9},
    },
    'phases': [
      {
        'sessions': [session],
        'weeks': 4,
      },
    ],
    'joined': {session: '2026-01-01T00:00:00.000Z'},
    'sessions': [
      {
        'id': session,
        'exercises': [
          {
            'id': slot,
            'exercise': exercise,
            'sets': [
              {
                'target': {'of': other, 'ofSlot': slot, 'share': 0.85},
              },
            ],
          },
        ],
      },
    ],
  };

  test('every id, as a key or a value, wherever it sits', () {
    expect(idsIn(body), {session, slot, exercise, other});
  });

  test('a copy names none of the original\'s ids', () {
    const student = '01900000-0000-7000-8000-00000000aaaa';
    final ids = copyIds(body, exercises: {exercise: student, other: other});
    final copy = remapIds(body, ids)! as Map;

    final left = idsIn(copy).difference({student, other});
    expect(left, isNot(contains(session)));
    expect(left, isNot(contains(slot)));
    expect(idsIn(copy), contains(student));
    expect((copy['rules'] as Map).containsKey(exercise), isFalse);
    expect((copy['rules'] as Map).containsKey(student), isTrue);
    expect((copy['joined'] as Map).keys.single, ids[session]);
    expect(isUuidV7(ids[session]!), isTrue, reason: 'anything else reads as no link');
  });

  test('what is not an id is left alone', () {
    final copy = remapIds(body, copyIds(body, exercises: const {}))! as Map;
    expect(copy['name'], 'Five three one');
    expect(((copy['phases'] as List).single as Map)['weeks'], 4);
  });

  test('two students get different ids for the same session', () {
    final one = copyIds(body, exercises: const {});
    final two = copyIds(body, exercises: const {});
    expect(one[session], isNot(two[session]));
  });

  test('an id an earlier send chose stays', () {
    const chosen = '01900000-0000-7000-8000-00000000bbbb';
    final ids = copyIds(body, exercises: const {}, known: {session: chosen});
    expect(ids[session], chosen);
  });

  test('saving gives every row an id, and keeps those it has', () {
    final identified = withRowIds({
      'sessions': [
        {
          'id': session,
          'exercises': [
            {
              'exercise': exercise,
              'sets': [<String, dynamic>{}],
            },
          ],
        },
      ],
    });
    final kept = (identified['sessions'] as List).single as Map;
    expect(kept['id'], session);
    final row = (kept['exercises'] as List).single as Map;
    expect(isUuidV7(row['id'] as String), isTrue);
    expect(isUuidV7(((row['sets'] as List).single as Map)['id'] as String), isTrue);
  });
}
