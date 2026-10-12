import 'package:heart/inputs/inputs.dart';
import 'package:heart/models/errors.dart';
import 'package:heart_models/heart_models.dart';
import 'package:test/test.dart';

import '../helpers/request.dart';

void main() {
  group('GoalCreateIn — objects / number(exclusiveMin) / parsed', () {
    test('parses a whole-workout goal with a stage ladder', () async {
      final input = await GoalCreateIn.fromRequest(
        jsonRequest(
          body: {
            'metric': 'workouts',
            'stages': [
              {'target': 3},
            ],
          },
        ),
      );
      expect(input.metric, GoalMetric.workouts);
      expect(input.stages, hasLength(1));
      expect(input.stages.first.target, 3);
    });

    test('rejects an unknown metric', () async {
      await expectLater(
        GoalCreateIn.fromRequest(
          jsonRequest(
            body: {
              'metric': 'nope',
              'stages': [
                {'target': 3},
              ],
            },
          ),
        ),
        throwsA(isA<BadRequest>()),
      );
    });

    test('rejects a non-positive target (number exclusiveMin)', () async {
      await expectLater(
        GoalCreateIn.fromRequest(
          jsonRequest(
            body: {
              'metric': 'workouts',
              'stages': [
                {'target': 0},
              ],
            },
          ),
        ),
        throwsA(isA<BadRequest>()),
      );
    });

    test('rejects missing or empty stages (objects)', () async {
      await expectLater(
        GoalCreateIn.fromRequest(jsonRequest(body: {'metric': 'workouts'})),
        throwsA(isA<BadRequest>()),
      );
      await expectLater(
        GoalCreateIn.fromRequest(jsonRequest(body: {'metric': 'workouts', 'stages': []})),
        throwsA(isA<BadRequest>()),
      );
    });
  });

  group('GoalUpdateIn — boolean', () {
    Map<String, dynamic> body({Object? archived}) => {
      'metric': 'workouts',
      'stages': [
        {'target': 3},
      ],
      'archived': ?archived,
    };

    test('defaults archived to false when absent', () async {
      final input = await GoalUpdateIn.fromRequest(jsonRequest(body: body()));
      expect(input.archived, isFalse);
    });

    test('reads archived: true', () async {
      final input = await GoalUpdateIn.fromRequest(jsonRequest(body: body(archived: true)));
      expect(input.archived, isTrue);
    });

    test('rejects a non-boolean archived', () async {
      await expectLater(GoalUpdateIn.fromRequest(jsonRequest(body: body(archived: 'yes'))), throwsA(isA<BadRequest>()));
    });
  });

  group('StageAchievedIn — required timestamp', () {
    test('parses a valid timestamp', () async {
      final input = await StageAchievedIn.fromRequest(jsonRequest(body: {'achievedAt': '2026-07-20T18:00:00Z'}));
      expect(input.achievedAt, DateTime.parse('2026-07-20T18:00:00Z'));
    });

    test('rejects a missing timestamp', () async {
      await expectLater(StageAchievedIn.fromRequest(jsonRequest(body: {})), throwsA(isA<BadRequest>()));
    });

    test('rejects an invalid timestamp', () async {
      await expectLater(
        StageAchievedIn.fromRequest(jsonRequest(body: {'achievedAt': 'nope'})),
        throwsA(isA<BadRequest>()),
      );
    });
  });
  group('goals about a subject (heart-api#196)', () {
    const exerciseId = '0198c1a2-b3c4-7d5e-8f60-718293a4b5c6';

    Future<GoalCreateIn> create(Map<String, dynamic> subject, {String metric = 'sessions'}) {
      return GoalCreateIn.fromRequest(
        jsonRequest(
          body: {
            'metric': metric,
            'cadence': 'week',
            ...subject,
            'stages': [
              {'target': 2},
            ],
          },
        ),
      );
    }

    Matcher rejected(String code) => throwsA(isA<BadRequest>().having((e) => e.code, 'code', code));

    test('sessions and sets take one subject: a pattern, a muscle or an exercise', () async {
      expect(
        (await create({'pattern': 'horizontal_press'})).goal.subject,
        const GoalSubject.pattern('horizontal_press'),
      );
      expect(
        (await create({'muscle': 'latissimus_dorsi'}, metric: 'sets')).goal.subject,
        const GoalSubject.muscle('latissimus_dorsi'),
      );
      expect(
        (await create({'exerciseId': exerciseId}, metric: 'sets')).goal.subject,
        const GoalSubject.exercise(exerciseId),
      );
    });

    test('a subject count names exactly one subject', () async {
      await expectLater(create({}), rejected('goal_scope'));
      await expectLater(create({'pattern': 'horizontal_press', 'muscle': 'chest'}), rejected('goal_scope'));
      await expectLater(create({'pattern': 'horizontal_press', 'exerciseId': exerciseId}), rejected('goal_scope'));
    });

    test('the older metrics keep their scope', () async {
      await expectLater(create({'pattern': 'horizontal_press'}, metric: 'workouts'), rejected('goal_scope'));
      await expectLater(create({'muscle': 'chest'}, metric: 'topSetWeight'), rejected('goal_scope'));
      await expectLater(
        create({'exerciseId': exerciseId, 'pattern': 'horizontal_press'}, metric: 'topSetWeight'),
        rejected('goal_scope'),
      );
    });

    test('a key is snake_case and short; which keys exist is the library\'s', () async {
      expect(
        (await create({'pattern': 'a_pattern_added_after_this_release'})).pattern,
        'a_pattern_added_after_this_release',
      );
      await expectLater(create({'pattern': 'Horizontal Press'}), rejected('invalid_subject'));
      await expectLater(create({'muscle': 7}), rejected('invalid_subject'));
      await expectLater(create({'muscle': 'x' * 65}), rejected('invalid_subject'));
    });

    test('an update carries the subject too', () async {
      final input = await GoalUpdateIn.fromRequest(
        jsonRequest(
          body: {
            'metric': 'sets',
            'muscle': 'chest',
            'cadence': 'week',
            'stages': [
              {'target': 12},
            ],
          },
        ),
      );
      expect(input.goal.subject, const GoalSubject.muscle('chest'));
    });
  });
}
