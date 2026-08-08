import 'package:heart/globals/config.dart';
import 'package:heart/inputs/inputs.dart';
import 'package:heart/models/errors.dart';
import 'package:heart_models/heart_models.dart';
import 'package:mockito/mockito.dart';
import 'package:relic_core/relic_core.dart';
import 'package:test/test.dart';

import '../helpers/request.dart';
import '../mocks.mocks.dart';

/// Exercises the request-parsing layer (`lib/inputs/parse.dart`) through the
/// typed input classes that use it — the private extensions can't be called
/// directly, and the input classes are the real contract anyway. Every parse
/// helper is covered here: happy path plus the `BadRequest` branch it throws.
void main() {
  group('PageQuery — integer / stringOrNull', () {
    PageQuery parse({Map<String, String> query = const {}, int defaultLimit = 30, int maxLimit = 100}) =>
        PageQuery.fromRequest(
          bareRequest(method: Method.get, query: query),
          defaultLimit: defaultLimit,
          maxLimit: maxLimit,
        );

    test('defaults the limit and leaves the cursor null when absent', () {
      final q = parse();
      expect(q.limit, 30);
      expect(q.cursor, isNull);
    });

    test('honours the defaultLimit override', () => expect(parse(defaultLimit: 20).limit, 20));

    test('clamps above max and below min', () {
      expect(parse(query: {'limit': '9999'}).limit, 100);
      expect(parse(query: {'limit': '0'}).limit, 1);
    });

    test('reads an explicit cursor + limit', () {
      final q = parse(query: {'limit': '25', 'cursor': 'abc'});
      expect(q.limit, 25);
      expect(q.cursor, 'abc');
    });

    test('treats an empty cursor as absent', () => expect(parse(query: {'cursor': ''}).cursor, isNull));

    test('rejects a non-integer limit', () {
      expect(() => parse(query: {'limit': 'abc'}), throwsA(isA<BadRequest>()));
    });
  });

  group('CommentsListQuery — required query string / parsed enum', () {
    CommentsListQuery parse(Map<String, String> query) =>
        CommentsListQuery.fromRequest(bareRequest(method: Method.get, query: query));

    const base = {'targetType': 'workout', 'targetId': 't-1'};

    test('parses targetType/targetId/cursor/limit', () {
      final q = parse({...base, 'cursor': 'c1', 'limit': '10'});
      expect(q.targetType, CommentTarget.workout);
      expect(q.targetId, 't-1');
      expect(q.cursor, 'c1');
      expect(q.limit, 10);
    });

    test('defaults the limit to 20 and clamps to 50', () {
      expect(parse(base).limit, 20);
      expect(parse({...base, 'limit': '999'}).limit, 50);
    });

    test(
      'rejects a missing targetId',
      () => expect(() => parse({'targetType': 'workout'}), throwsA(isA<BadRequest>())),
    );

    test('rejects an unknown targetType', () {
      expect(() => parse({...base, 'targetType': 'nope'}), throwsA(isA<BadRequest>()));
    });
  });

  group('CommentCreateIn — required string / maxLength / parsed enum', () {
    const valid = {'targetType': 'workout', 'targetId': 't-1', 'body': 'nice'};

    test('parses a valid comment', () async {
      final input = await CommentCreateIn.fromRequest(jsonRequest(body: valid));
      expect(input.targetType, CommentTarget.workout);
      expect(input.targetId, 't-1');
      expect(input.body, 'nice');
    });

    test('rejects an unknown targetType', () async {
      await expectLater(
        CommentCreateIn.fromRequest(jsonRequest(body: {...valid, 'targetType': 'nope'})),
        throwsA(isA<BadRequest>()),
      );
    });

    test('rejects a missing or empty body', () async {
      await expectLater(
        CommentCreateIn.fromRequest(jsonRequest(body: {'targetType': 'workout', 'targetId': 't-1'})),
        throwsA(isA<BadRequest>()),
      );
      await expectLater(
        CommentCreateIn.fromRequest(jsonRequest(body: {...valid, 'body': ''})),
        throwsA(isA<BadRequest>()),
      );
    });

    test('rejects a body over the max length', () async {
      await expectLater(
        CommentCreateIn.fromRequest(jsonRequest(body: {...valid, 'body': 'x' * 5001})),
        throwsA(isA<BadRequest>()),
      );
    });
  });

  group('WorkoutPatchIn — dateOrNull / string / cross-field', () {
    test('parses name + start + end', () async {
      final input = await WorkoutPatchIn.fromRequest(
        jsonRequest(body: {'name': 'A', 'start': '2026-07-20T18:00:00Z', 'end': '2026-07-20T19:00:00Z'}),
      );
      expect(input.name, 'A');
      expect(input.start, DateTime.parse('2026-07-20T18:00:00Z'));
      expect(input.end, DateTime.parse('2026-07-20T19:00:00Z'));
    });

    test('a name-only patch leaves the times null', () async {
      final input = await WorkoutPatchIn.fromRequest(jsonRequest(body: {'name': 'A'}));
      expect(input.start, isNull);
      expect(input.end, isNull);
      expect(input.calories, isNull);
    });

    test('a calories-only patch is accepted', () async {
      final input = await WorkoutPatchIn.fromRequest(jsonRequest(body: {'calories': 421.5}));
      expect(input.calories, 421.5);
      expect(input.name, isNull);
    });

    test('rejects negative calories', () async {
      await expectLater(
        WorkoutPatchIn.fromRequest(jsonRequest(body: {'calories': -1})),
        throwsA(isA<BadRequest>()),
      );
    });

    test('rejects non-numeric calories', () async {
      await expectLater(
        WorkoutPatchIn.fromRequest(jsonRequest(body: {'calories': 'many'})),
        throwsA(isA<BadRequest>()),
      );
    });

    test('rejects an empty body (no fields)', () async {
      await expectLater(WorkoutPatchIn.fromRequest(jsonRequest(body: {})), throwsA(isA<BadRequest>()));
    });

    test('rejects end before start', () async {
      await expectLater(
        WorkoutPatchIn.fromRequest(jsonRequest(body: {'start': '2026-07-20T19:00:00Z', 'end': '2026-07-20T18:00:00Z'})),
        throwsA(isA<BadRequest>()),
      );
    });

    test('rejects a blank name', () async {
      await expectLater(WorkoutPatchIn.fromRequest(jsonRequest(body: {'name': ''})), throwsA(isA<BadRequest>()));
    });

    test('rejects an unparseable date', () async {
      await expectLater(
        WorkoutPatchIn.fromRequest(jsonRequest(body: {'start': 'not-a-date'})),
        throwsA(isA<BadRequest>()),
      );
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

  group('DeviceRegisterIn — mapping / parsed enum', () {
    late MockAppConfig config;

    setUp(() {
      config = MockAppConfig();
      when(config.supportedLocales).thenReturn(const ['en']);
      when(config.defaultLocale).thenReturn('en');
    });

    Future<DeviceRegisterIn> parse(Map<String, dynamic> body) =>
        DeviceRegisterIn.fromRequest(jsonRequest(body: body)..config = config);

    test('parses platform / token / settings', () async {
      final input = await parse({
        'platform': 'ios',
        'token': 'tok',
        'settings': {'a': 1},
      });
      expect(input.platform, DevicePlatform.ios);
      expect(input.token, 'tok');
      expect(input.settings, containsPair('a', 1));
    });

    test('defaults settings to empty when absent (mapping orElse)', () async {
      final input = await parse({'platform': 'ios', 'token': 'tok'});
      expect(input.settings, isEmpty);
    });

    test('rejects a non-object settings', () async {
      await expectLater(parse({'platform': 'ios', 'token': 'tok', 'settings': 'x'}), throwsA(isA<BadRequest>()));
    });

    test('rejects an unknown platform', () async {
      await expectLater(parse({'platform': 'nope', 'token': 'tok'}), throwsA(isA<BadRequest>()));
    });

    test('rejects a missing token', () async {
      await expectLater(parse({'platform': 'ios'}), throwsA(isA<BadRequest>()));
    });
  });
}
