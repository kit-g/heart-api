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

  void access({String owner = 'owner', bool related = true, bool readable = true, bool exists = true}) {
    when(
      app.db.accessOfTarget(
        readerId: anyNamed('readerId'),
        targetType: anyNamed('targetType'),
        targetId: anyNamed('targetId'),
      ),
    ).thenAnswer((_) async => exists ? (ownerId: owner, related: related, readable: readable) : null);
  }

  void sets({required bool created}) {
    when(
      app.db.setReaction(
        authorId: anyNamed('authorId'),
        targetType: anyNamed('targetType'),
        targetId: anyNamed('targetId'),
        kind: anyNamed('kind'),
      ),
    ).thenAnswer((i) async => (reaction(kind: i.namedArguments[#kind] as String), created));
    when(app.config.eventsQueueUrl).thenReturn('https://sqs.test/events');
    when(app.events.publish(queueUrl: anyNamed('queueUrl'), message: anyNamed('message'))).thenAnswer((_) async {});
  }

  group('PUT /reactions/:targetType/:targetId', () {
    test('a new reaction is 201, and the owner hears which kind of thing it is on', () async {
      access();
      sets(created: true);

      final res = await app.send('PUT', '/reactions/exercise_set/$set', body: {'kind': 'cheer'});

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
      verify(app.db.setReaction(authorId: 'u1', targetType: CommentTarget.exerciseSet, targetId: set, kind: 'cheer'));
    });

    test('a changed word is 200, and tells nobody', () async {
      access();
      sets(created: false);

      final res = await app.send('PUT', '/reactions/workout/$workout', body: {'kind': 'like'});

      expect(res.status, 200);
      verifyNever(app.events.publish(queueUrl: anyNamed('queueUrl'), message: anyNamed('message')));
    });

    test('reacting to one\'s own workout tells nobody', () async {
      access(owner: 'u1');
      sets(created: true);

      expect((await app.send('PUT', '/reactions/workout/$workout', body: {'kind': 'cheer'})).status, 201);
      verifyNever(app.events.publish(queueUrl: anyNamed('queueUrl'), message: anyNamed('message')));
    });

    test('a word that isn\'t a reaction is refused before anything is read', () async {
      final res = await app.send('PUT', '/reactions/workout/$workout', body: {'kind': 'heartRate'});
      expect(res.status, 400);
      expect((jsonDecode(res.body) as Map)['code'], 'invalid_kind');
      verifyZeroInteractions(app.db);
    });

    test('a target that can\'t be one is a 404, before anything is read', () async {
      for (final path in ['comment/$workout', 'workout/not-an-id']) {
        expect((await app.send('PUT', '/reactions/$path', body: {'kind': 'cheer'})).status, 404, reason: path);
      }
      verifyZeroInteractions(app.db);
    });

    test('a stranger is refused, and what the reader can\'t see is missing', () async {
      access(related: false, readable: false);
      expect((await app.send('PUT', '/reactions/workout/$workout', body: {'kind': 'cheer'})).status, 403);

      access(readable: false);
      expect((await app.send('PUT', '/reactions/workout/$workout', body: {'kind': 'cheer'})).status, 404);

      access(exists: false);
      expect((await app.send('PUT', '/reactions/workout/$workout', body: {'kind': 'cheer'})).status, 404);

      verifyNever(
        app.db.setReaction(
          authorId: anyNamed('authorId'),
          targetType: anyNamed('targetType'),
          targetId: anyNamed('targetId'),
          kind: anyNamed('kind'),
        ),
      );
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
    access();
    when(
      app.db.listReactions(
        targetType: anyNamed('targetType'),
        targetId: anyNamed('targetId'),
        cursor: anyNamed('cursor'),
        limit: anyNamed('limit'),
      ),
    ).thenAnswer((_) async => Page(items: [reaction()], hasMore: true));
    when(
      app.db.summarizeReactions(
        readerId: anyNamed('readerId'),
        targetType: anyNamed('targetType'),
        targetId: anyNamed('targetId'),
      ),
    ).thenAnswer((_) async => (counts: {'cheer': 3, 'like': 1}, mine: 'cheer'));

    final res = await app.send('GET', '/reactions/workout/$workout?limit=1');

    expect(res.status, 200);
    final read = Reactions.fromJson(jsonDecode(res.body) as Map);
    expect(read.reactions.single.kind, 'cheer');
    expect(read.counts, {'cheer': 3, 'like': 1});
    expect(read.mine, 'cheer');
    expect(read.cursor, '01900000-0000-7000-8000-0000000000b1');
    verify(app.db.listReactions(targetType: CommentTarget.workout, targetId: workout, cursor: null, limit: 1));
  });

  test('a cursor that was never one is a 400', () async {
    expect((await app.send('GET', '/reactions/workout/$workout?cursor=zzz')).status, 400);
  });
}
