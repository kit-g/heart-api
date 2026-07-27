import 'package:heart/inputs/inputs.dart';
import 'package:heart/models/errors.dart';
import 'package:heart_models/heart_models.dart';
import 'package:relic_core/relic_core.dart';
import 'package:test/test.dart';

import '../helpers/request.dart';

void main() {
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
}
