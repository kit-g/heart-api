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
}
