import 'dart:convert';

import 'package:heart_models/heart_models.dart';
import 'package:mockito/mockito.dart';
import 'package:test/test.dart';

import '../helpers/app_harness.dart';

void main() {
  late AppHarness app;

  setUp(() async => app = await AppHarness.start());
  tearDown(() => app.stop());

  const workout = '01900000-0000-7000-8000-0000000000a1';
  const set = '01900000-0000-7000-8000-0000000000a2';

  Reaction reaction({String kind = 'cheer', CommentTarget target = .workout, String id = workout}) {
    return Reaction(
      id: '01900000-0000-7000-8000-0000000000b1',
      authorId: 'u1',
      kind: kind,
      targetType: target,
      targetId: id,
      createdAt: DateTime.utc(2026, 11, 8),
    );
  }

  void sets({required bool created, String? notify}) {
    when(
      app.db.setReaction(
        authorId: anyNamed('authorId'),
        targetType: anyNamed('targetType'),
        targetId: anyNamed('targetId'),
        kind: anyNamed('kind'),
        at: anyNamed('at'),
      ),
    ).thenAnswer(
      (i) async => (reaction: reaction(kind: i.namedArguments[#kind] as String), created: created, notify: notify),
    );
    when(app.config.eventsQueueUrl).thenReturn('https://sqs.test/events');
    when(app.events.publish(queueUrl: anyNamed('queueUrl'), message: anyNamed('message'))).thenAnswer((_) async {});
  }

  group('PUT /reactions/:targetType/:targetId', () {
    test('a first reaction is 201, and the owner the service names hears what it is on', () async {
      sets(created: true, notify: 'owner');

      final res = await app.send(
        'PUT',
        '/reactions/exercise_set/$set',
        body: {'kind': 'cheer', 'at': '2026-11-01T09:00:00.000Z'},
      );

      expect(res.status, 201);
      expect((jsonDecode(res.body) as Map)['kind'], 'cheer');
      final message =
          verify(app.events.publish(queueUrl: anyNamed('queueUrl'), message: captureAnyNamed('message')))
                  .captured
                  .single
              as Map;
      expect(message['userId'], 'owner');
      expect(message['topic'], 'reaction.created');
      expect(message['variant'], 'exercise_set');
      expect(message['data'], {'targetType': 'exercise_set', 'targetId': set});
      verify(
        app.db.setReaction(
          authorId: 'u1',
          targetType: CommentTarget.exerciseSet,
          targetId: set,
          kind: 'cheer',
          at: DateTime.utc(2026, 11, 1, 9),
        ),
      );
    });

    test('a changed word is 200, and nobody the service doesn\'t name hears of anything', () async {
      sets(created: false);
      expect((await app.send('PUT', '/reactions/workout/$workout', body: {'kind': 'like'})).status, 200);

      sets(created: true);
      expect((await app.send('PUT', '/reactions/workout/$workout', body: {'kind': 'like'})).status, 201);

      verifyNever(app.events.publish(queueUrl: anyNamed('queueUrl'), message: anyNamed('message')));
    });

    test('a word that isn\'t a reaction, or a time that isn\'t one, is refused before anything is read', () async {
      final res = await app.send('PUT', '/reactions/workout/$workout', body: {'kind': 'heartRate'});
      expect(res.status, 400);
      expect((jsonDecode(res.body) as Map)['code'], 'invalid_kind');
      expect((await app.send('PUT', '/reactions/workout/$workout', body: {'kind': 'cheer', 'at': 'soon'})).status, 400);
      verifyZeroInteractions(app.db);
    });

    test('a target that can\'t be one is a 404, before anything is read', () async {
      for (final path in ['comment/$workout', 'workout/not-an-id']) {
        expect((await app.send('PUT', '/reactions/$path', body: {'kind': 'cheer'})).status, 404, reason: path);
      }
      verifyZeroInteractions(app.db);
    });
  });

  test('taking a reaction off is 204, whether or not there was one, and needs no read', () async {
    when(
      app.db.removeReaction(
        authorId: anyNamed('authorId'),
        targetType: anyNamed('targetType'),
        targetId: anyNamed('targetId'),
      ),
    ).thenAnswer((_) async {});

    expect((await app.send('DELETE', '/reactions/workout/$workout')).status, 204);
    verify(app.db.removeReaction(authorId: 'u1', targetType: CommentTarget.workout, targetId: workout)).called(1);
  });

  test('the list carries the counts and the reader\'s own, and pages', () async {
    when(
      app.db.getReactions(
        readerId: anyNamed('readerId'),
        targetType: anyNamed('targetType'),
        targetId: anyNamed('targetId'),
        cursor: anyNamed('cursor'),
        limit: anyNamed('limit'),
      ),
    ).thenAnswer(
      (_) async => (
        page: Page(items: [reaction()], hasMore: true),
        summary: (counts: {'cheer': 3, 'like': 1}, mine: 'cheer'),
      ),
    );

    final res = await app.send('GET', '/reactions/workout/$workout?limit=1');

    expect(res.status, 200);
    final read = Reactions.fromJson(jsonDecode(res.body) as Map);
    expect(read.reactions.single.kind, 'cheer');
    expect(read.counts, {'cheer': 3, 'like': 1});
    expect(read.mine, 'cheer');
    expect(read.cursor, '01900000-0000-7000-8000-0000000000b1');
    verify(
      app.db.getReactions(readerId: 'u1', targetType: CommentTarget.workout, targetId: workout, cursor: null, limit: 1),
    );
  });

  test('a cursor that was never one is a 400', () async {
    expect((await app.send('GET', '/reactions/workout/$workout?cursor=zzz')).status, 400);
  });
}
