import 'package:heart/inputs/inputs.dart';
import 'package:heart/models/errors.dart';
import 'package:test/test.dart';

import '../helpers/request.dart';

void main() {
  const id = '01900000-0000-7000-8000-000000000001';

  Future<WorkoutPlanIn> parse(Object? plan) => WorkoutPlanIn.fromRequest(jsonRequest(body: {'plan': plan}));

  test('what the server reads, and whatever else the device keeps in it', () async {
    final input = await parse({
      'week': 2,
      'exercises': [
        {
          'name': 'kept',
          'sets': [
            {'weight': 80, 'setId': id, 'reps': 5},
            {'weight': null},
            <String, dynamic>{},
          ],
        },
      ],
    });
    expect(input.plan['week'], 2);
  });

  test('no exercises is a plan with nothing to compare', () async {
    expect((await parse({'week': 1})).plan, {'week': 1});
  });

  for (final (name, plan) in <(String, Object?)>[
    ('not an object', 'plan'),
    ('empty', <String, dynamic>{}),
    (
      'exercises not a list',
      {
        'exercises': {'x': 1},
      },
    ),
    (
      'an exercise not an object',
      {
        'exercises': [1],
      },
    ),
    (
      'sets not a list',
      {
        'exercises': [
          {'sets': 1},
        ],
      },
    ),
    (
      'a set not an object',
      {
        'exercises': [
          {
            'sets': [1],
          },
        ],
      },
    ),
    (
      'a weight not a number',
      {
        'exercises': [
          {
            'sets': [
              {'weight': 'heavy'},
            ],
          },
        ],
      },
    ),
    (
      'a setId not an id',
      {
        'exercises': [
          {
            'sets': [
              {'setId': 'nope'},
            ],
          },
        ],
      },
    ),
  ]) {
    test('refuses $name', () async {
      await expectLater(
        parse(plan),
        throwsA(isA<BadRequest>().having((e) => e.code, 'code', 'invalid_plan')),
      );
    });
  }
}
