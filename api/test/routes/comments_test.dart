import 'package:heart/globals/config.dart';
import 'package:heart/globals/globals.dart';
import 'package:heart/middleware/database.dart';
import 'package:heart/middleware/events.dart';
import 'package:heart/models/errors.dart';
import 'package:heart/routes/comments.dart';
import 'package:heart_models/heart_models.dart';
import 'package:mockito/mockito.dart';
import 'package:relic_core/relic_core.dart';
import 'package:test/test.dart';

import '../helpers/request.dart';
import '../mocks.mocks.dart';

const _workoutId = '019def00-0000-7000-8000-000000000001';
const _ownerId = 'owner-id';
const _meId = 'u1';

Comment _fakeComment({
  String id = 'c-1',
  CommentTarget target = .workout,
  String body = 'nice',
}) {
  return Comment(
    id: id,
    authorId: _meId,
    body: body,
    targetType: target,
    targetId: _workoutId,
    createdAt: DateTime.utc(2026, 5, 12),
  );
}

void main() {
  late MockCommentService commentService;
  late MockConnectionsService connections;
  late MockEventPublisher publisher;
  late MockAppConfig config;

  setUp(() {
    commentService = MockCommentService();
    connections = MockConnectionsService();
    publisher = MockEventPublisher();
    config = MockAppConfig();
    when(config.eventsQueueUrl).thenReturn('https://sqs.test/heart-api-events');
    when(config.firebaseEventsQueueUrl).thenReturn('https://sqs.test/heart-firebase-events');
    when(config.defaultLocale).thenReturn('en');
    when(
      publisher.publish(queueUrl: anyNamed('queueUrl'), message: anyNamed('message')),
    ).thenAnswer((_) async {});
  });

  Request wire(Request req) {
    return req
      ..user = User(id: _meId, displayName: 'Sarah')
      ..config = config
      ..commentService = commentService
      ..connectionsService = connections
      ..events = publisher;
  }

  group('createComment', () {
    Map<String, dynamic> validBody = {
      'targetType': 'workout',
      'targetId': _workoutId,
      'body': 'nice',
    };

    setUp(() {
      when(
        commentService.ownerOfTarget(
          targetType: anyNamed('targetType'),
          targetId: anyNamed('targetId'),
        ),
      ).thenAnswer((_) async => _ownerId);
      when(
        commentService.createComment(
          authorId: anyNamed('authorId'),
          targetType: anyNamed('targetType'),
          targetId: anyNamed('targetId'),
          body: anyNamed('body'),
        ),
      ).thenAnswer((_) async => _fakeComment());
    });

    test('owner comments on own content: no connection check, no notification enqueue', () async {
      when(
        commentService.ownerOfTarget(
          targetType: anyNamed('targetType'),
          targetId: anyNamed('targetId'),
        ),
      ).thenAnswer((_) async => _meId);

      final req = wire(jsonRequest(path: '/comments', body: validBody));
      await createComment(req);

      verifyNever(connections.areConnected(userA: anyNamed('userA'), userB: anyNamed('userB')));
      verify(
        commentService.createComment(
          authorId: _meId,
          targetType: CommentTarget.workout,
          targetId: _workoutId,
          body: 'nice',
        ),
      ).called(1);
      verifyNever(publisher.publish(queueUrl: anyNamed('queueUrl'), message: anyNamed('message')));
    });

    test('connected user comments: enqueues comment.created with snippet + authorName', () async {
      when(
        connections.areConnected(userA: _meId, userB: _ownerId),
      ).thenAnswer((_) async => true);

      final req = wire(jsonRequest(path: '/comments', body: validBody));
      await createComment(req);

      verify(connections.areConnected(userA: _meId, userB: _ownerId)).called(1);
      verify(
        commentService.createComment(
          authorId: _meId,
          targetType: CommentTarget.workout,
          targetId: _workoutId,
          body: 'nice',
        ),
      ).called(1);

      final captured = verify(
        publisher.publish(
          queueUrl: 'https://sqs.test/heart-api-events',
          message: captureAnyNamed('message'),
        ),
      ).captured.single as Map<String, dynamic>;
      expect(captured['type'], 'comment.created');
      expect(captured['ownerId'], _ownerId);
      expect(captured['authorId'], _meId);
      expect(captured['authorName'], 'Sarah');
      expect(captured['targetType'], 'workout');
      expect(captured['body'], 'nice');
    });

    test('rejects a non-connected, non-owner user', () async {
      when(
        connections.areConnected(userA: _meId, userB: _ownerId),
      ).thenAnswer((_) async => false);

      final req = wire(jsonRequest(path: '/comments', body: validBody));
      await expectLater(createComment(req), throwsA(isA<Forbidden>()));

      verifyNever(
        commentService.createComment(
          authorId: anyNamed('authorId'),
          targetType: anyNamed('targetType'),
          targetId: anyNamed('targetId'),
          body: anyNamed('body'),
        ),
      );
    });

    test('404 when target does not exist', () async {
      when(
        commentService.ownerOfTarget(
          targetType: anyNamed('targetType'),
          targetId: anyNamed('targetId'),
        ),
      ).thenAnswer((_) async => null);

      final req = wire(jsonRequest(path: '/comments', body: validBody));
      await expectLater(createComment(req), throwsA(isA<NotFound>()));
    });

    test('rejects missing body / targetId / targetType', () async {
      for (final missing in [
        {'targetId': _workoutId, 'body': 'x'},
        {'targetType': 'workout', 'body': 'x'},
        {'targetType': 'workout', 'targetId': _workoutId},
      ]) {
        final req = wire(jsonRequest(path: '/comments', body: missing));
        await expectLater(createComment(req), throwsA(isA<BadRequest>()));
      }
    });

    test('rejects unknown targetType', () async {
      final req = wire(jsonRequest(
        path: '/comments',
        body: {'targetType': 'set', 'targetId': _workoutId, 'body': 'x'},
      ));
      await expectLater(createComment(req), throwsA(isA<BadRequest>()));
    });
  });

  group('listComments', () {
    setUp(() {
      when(
        commentService.ownerOfTarget(
          targetType: anyNamed('targetType'),
          targetId: anyNamed('targetId'),
        ),
      ).thenAnswer((_) async => _meId);
      when(
        commentService.listComments(
          targetType: anyNamed('targetType'),
          targetId: anyNamed('targetId'),
          cursor: anyNamed('cursor'),
          limit: anyNamed('limit'),
        ),
      ).thenAnswer((_) async => Page(items: [_fakeComment()], hasMore: false));
    });

    test('returns comments for the owner without a cursor when no next page', () async {
      final req = wire(jsonRequest(
        method: Method.get,
        path: '/comments',
        query: {'targetType': 'workout', 'targetId': _workoutId},
      ));
      final result = await listComments(req);
      expect(result.toMap()['comments'], hasLength(1));
      expect(result.toMap().containsKey('cursor'), isFalse);
    });

    test('emits cursor only when there is a next page', () async {
      when(
        commentService.listComments(
          targetType: anyNamed('targetType'),
          targetId: anyNamed('targetId'),
          cursor: anyNamed('cursor'),
          limit: anyNamed('limit'),
        ),
      ).thenAnswer(
        (_) async => Page(items: [_fakeComment(id: 'c-1'), _fakeComment(id: 'c-2')], hasMore: true),
      );

      final req = wire(jsonRequest(
        method: Method.get,
        path: '/comments',
        query: {'targetType': 'workout', 'targetId': _workoutId},
      ));
      final result = await listComments(req);
      expect(result.toMap()['cursor'], 'c-2');
    });

    test('clamps limit to the max', () async {
      final req = wire(jsonRequest(
        method: Method.get,
        path: '/comments',
        query: {'targetType': 'workout', 'targetId': _workoutId, 'limit': '999'},
      ));
      await listComments(req);
      verify(commentService.listComments(
        targetType: CommentTarget.workout,
        targetId: _workoutId,
        cursor: null,
        limit: 50,
      )).called(1);
    });

    test('Forbidden when neither owner nor connected', () async {
      when(
        commentService.ownerOfTarget(
          targetType: anyNamed('targetType'),
          targetId: anyNamed('targetId'),
        ),
      ).thenAnswer((_) async => _ownerId);
      when(
        connections.areConnected(userA: _meId, userB: _ownerId),
      ).thenAnswer((_) async => false);

      final req = wire(jsonRequest(
        method: Method.get,
        path: '/comments',
        query: {'targetType': 'workout', 'targetId': _workoutId},
      ));
      await expectLater(listComments(req), throwsA(isA<Forbidden>()));
    });
  });

  group('editCommentById', () {
    test('passes through to the service', () async {
      when(
        commentService.editComment(
          commentId: anyNamed('commentId'),
          authorId: anyNamed('authorId'),
          body: anyNamed('body'),
        ),
      ).thenAnswer((_) async => _fakeComment(body: 'edited'));

      final req = wire(jsonRequest(path: '/comments/c-1', body: {'body': 'edited'}));
      final out = await editCommentById(req, 'c-1');
      expect(out.body, 'edited');
      verify(commentService.editComment(commentId: 'c-1', authorId: _meId, body: 'edited')).called(1);
    });

    test('rejects empty body', () async {
      final req = wire(jsonRequest(path: '/comments/c-1', body: {'body': ''}));
      await expectLater(editCommentById(req, 'c-1'), throwsA(isA<BadRequest>()));
    });
  });

  group('deleteCommentById', () {
    test('204 on success', () async {
      when(
        commentService.deleteComment(commentId: anyNamed('commentId'), authorId: anyNamed('authorId')),
      ).thenAnswer((_) async {});

      final req = wire(jsonRequest(method: Method.delete, path: '/comments/c-1'));
      await expectLater(deleteCommentById(req, 'c-1'), throwsA(isA<NoContent>()));
      verify(commentService.deleteComment(commentId: 'c-1', authorId: _meId)).called(1);
    });
  });
}