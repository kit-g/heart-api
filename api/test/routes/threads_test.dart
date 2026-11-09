import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:heart/notifications/sealing.dart';
import 'package:heart_models/heart_models.dart';
import 'package:mockito/mockito.dart';
import 'package:test/test.dart';

import '../helpers/app_harness.dart';

void main() {
  late AppHarness app;

  setUp(() async => app = await AppHarness.start());
  tearDown(() => app.stop());

  const thread = '01900000-0000-7000-8000-000000000001';
  const item = '01900000-0000-7000-8000-000000000002';
  final commitment = base64.encode(List.filled(32, 1));

  Map<String, dynamic> body({Object? content = 'sealed', Object? kind, Object? commit}) => {
    'id': item,
    'content': content,
    'commitment': commit ?? commitment,
    'at': '2026-11-01T00:00:00.000Z',
    'kind': ?kind,
  };

  group('POST /threads/:id/items', () {
    test('content is a string, so nothing readable rides in structure', () async {
      final res = await app.send('POST', '/threads/$thread/items', body: body(content: {'text': 'hi'}));
      expect(res.status, 400);
    });

    test('over 16 KB is refused', () async {
      final res = await app.send('POST', '/threads/$thread/items', body: body(content: 'x' * 16385));
      expect(res.status, 400);
    });

    test('a kind nobody opened is refused', () async {
      final res = await app.send('POST', '/threads/$thread/items', body: body(kind: 'skip_reason'));
      expect(res.status, 400);
      expect(res.body, contains('invalid_kind'));
    });

    test('a reaction is to a message, named by its id', () async {
      for (final subject in [
        <String, dynamic>{},
        {'subjectType': 'workout', 'subjectId': item},
        {'subjectType': 'message', 'subjectId': 'not-an-id'},
      ]) {
        final res = await app.send(
          'POST',
          '/threads/$thread/items',
          body: {
            ...body(kind: 'reaction'),
            ...subject,
          },
        );
        expect(res.status, 400, reason: '$subject');
        expect(res.body, contains('invalid_subject'), reason: '$subject');
      }
    });

    test('a commitment is 32 bytes', () async {
      final res = await app.send('POST', '/threads/$thread/items', body: body(commit: base64.encode([1, 2, 3])));
      expect(res.status, 400);
      expect(res.body, contains('invalid_commitment'));
    });

    test('a thread that can take nothing says so', () async {
      when(
        app.db.getThreadParties(senderId: anyNamed('senderId'), threadId: anyNamed('threadId')),
      ).thenAnswer((_) async => null);
      final res = await app.send('POST', '/threads/$thread/items', body: body());
      expect(res.status, 403);
      expect(res.body, contains('thread_closed'));
    });
  });

  group('posting through the real app', () {
    void stubSend({bool created = true}) {
      when(app.config.messageTags).thenReturn(MessageTags({'k': List.filled(32, 1)}));
      when(app.config.eventsQueueUrl).thenReturn('https://sqs.test/events');
      when(app.events.publish(queueUrl: anyNamed('queueUrl'), message: anyNamed('message'))).thenAnswer((_) async {});
      when(
        app.db.getThreadParties(senderId: anyNamed('senderId'), threadId: anyNamed('threadId')),
      ).thenAnswer((_) async => (threadId: thread, senderId: 'me', recipientId: 'them', connectionId: 'c1'));
      when(
        app.db.addThreadItem(
          senderId: anyNamed('senderId'),
          threadId: anyNamed('threadId'),
          id: anyNamed('id'),
          kind: anyNamed('kind'),
          content: anyNamed('content'),
          commitment: anyNamed('commitment'),
          tag: anyNamed('tag'),
          tagKey: anyNamed('tagKey'),
          at: anyNamed('at'),
          createdAt: anyNamed('createdAt'),
          subjectType: anyNamed('subjectType'),
          subjectId: anyNamed('subjectId'),
        ),
      ).thenAnswer(
        (_) async => (
          ThreadItem(
            id: item,
            threadId: thread,
            kind: 'message',
            content: 'sealed',
            commitment: commitment,
            tag: 't',
            tagKey: 'k',
            at: DateTime.utc(2026),
            createdAt: DateTime.utc(2026),
          ),
          created,
        ),
      );
    }

    Map published() {
      return verify(
            app.events.publish(queueUrl: anyNamed('queueUrl'), message: captureAnyNamed('message')),
          ).captured.single
          as Map;
    }

    test('tells the other person', () async {
      stubSend();
      final res = await app.send('POST', '/threads/$thread/items', body: body());
      expect(res.status, 201);
      final message = published();
      expect(message['userId'], 'them');
      expect(message.toString(), isNot(contains('sealed')));
    });

    test('a reaction to a message is stored, and pushes nothing', () async {
      stubSend();
      final res = await app.send(
        'POST',
        '/threads/$thread/items',
        body: {
          ...body(kind: 'reaction'),
          'subjectType': 'message',
          'subjectId': item,
        },
      );
      expect(res.status, 201);
      verifyNever(app.events.publish(queueUrl: anyNamed('queueUrl'), message: anyNamed('message')));
    });

    test('names the connection, so their setting for this one person applies', () async {
      stubSend();
      await app.send('POST', '/threads/$thread/items', body: body());
      expect(published()['connectionId'], 'c1');
    });

    test('a retry tells them again, in case the push is what failed the first time', () async {
      stubSend(created: false);
      final res = await app.send('POST', '/threads/$thread/items', body: body());
      expect(res.status, 200);
      expect(published()['userId'], 'them');
    });

    test('tags a time a device keeping milliseconds can write back exactly', () async {
      stubSend();
      await app.send('POST', '/threads/$thread/items', body: body());
      final captured = verify(
        app.db.addThreadItem(
          senderId: anyNamed('senderId'),
          threadId: anyNamed('threadId'),
          id: anyNamed('id'),
          kind: anyNamed('kind'),
          content: anyNamed('content'),
          commitment: anyNamed('commitment'),
          tag: captureAnyNamed('tag'),
          tagKey: anyNamed('tagKey'),
          at: anyNamed('at'),
          createdAt: captureAnyNamed('createdAt'),
          subjectType: anyNamed('subjectType'),
          subjectId: anyNamed('subjectId'),
        ),
      ).captured;
      final tag = captured.whereType<String>().single;
      final stored = captured.whereType<DateTime>().single;
      final kept = DateTime.fromMillisecondsSinceEpoch(stored.millisecondsSinceEpoch, isUtc: true);
      expect(
        MessageTags({'k': List.filled(32, 1)})
            .tag(commitment: commitment, senderId: 'u1', recipientId: 'them', at: kept),
        tag,
      );
    });
  });

  test('a cleared thread wakes the other person, unless they blocked whoever cleared it', () async {
    when(app.config.eventsQueueUrl).thenReturn('https://sqs.test/events');
    when(app.events.publish(queueUrl: anyNamed('queueUrl'), message: anyNamed('message'))).thenAnswer((_) async {});
    when(app.db.clearThread(userId: anyNamed('userId'), threadId: anyNamed('threadId')))
        .thenAnswer((_) async => 'them');

    final res = await app.send('DELETE', '/threads/$thread/items');
    expect(res.status, 204);
    final message =
        verify(app.events.publish(queueUrl: anyNamed('queueUrl'), message: captureAnyNamed('message'))).captured.single
            as Map;
    expect(message['userId'], 'them');
    expect(message['actorId'], 'u1', reason: 'the send path checks blocks between the two');
  });

  group('an id that can\'t be one answers before the database sees it', () {
    test('in a path', () async {
      expect((await app.send('POST', '/connections/them:PEER:fitness/thread')).status, 404);
      expect((await app.send('GET', '/threads/x/items')).status, 404);
      expect((await app.send('PUT', '/threads/x/read', body: {'cursor': 'c'})).status, 404);
      expect((await app.send('DELETE', '/notes/x')).status, 404);
    });

    test('in a query', () async {
      expect((await app.send('GET', '/notes?connectionId=x')).status, 400);
      expect((await app.send('GET', '/notes?cursor=x')).status, 400);
    });
  });

  test('a NUL, which the database can\'t store, is refused up front', () async {
    final res = await app.send('POST', '/threads/$thread/items', body: body(content: 'sealed\u0000'));
    expect(res.status, 400);
  });

  group('a report', () {
    // The reporter is the harness's user; the words are tagged by the same key.
    final tags = MessageTags({'k': List.filled(32, 1)});
    final key = base64.encode(List.filled(32, 7));
    const words = 'words';
    final committed = base64.encode(Hmac(sha256, base64.decode(key)).convert(utf8.encode(words)).bytes);
    final at = DateTime.utc(2026, 11);

    Map<String, dynamic> message({required String from, required String to}) => {
      'words': words,
      'key': key,
      'commitment': committed,
      'tag': tags.tag(commitment: committed, senderId: from, recipientId: to, at: at),
      'tagKey': 'k',
      'senderId': from,
      'recipientId': to,
      'createdAt': at.toIso8601String(),
    };

    Future<bool> verified(List<Map<String, dynamic>> messages, {String reportedId = 'them'}) async {
      when(app.config.reportReviewKey).thenReturn(base64.encode(List.filled(32, 1)));
      when(app.config.messageTags).thenReturn(tags);
      when(
        app.db.fileReport(
          reporterId: anyNamed('reporterId'),
          reportedId: anyNamed('reportedId'),
          connectionId: anyNamed('connectionId'),
          reason: anyNamed('reason'),
          sealed: anyNamed('sealed'),
          verified: anyNamed('verified'),
        ),
      ).thenAnswer((_) async {});
      await app.send('POST', '/reports', body: {'reportedId': reportedId, 'reason': 'abuse', 'messages': messages});
      return verify(
            app.db.fileReport(
              reporterId: anyNamed('reporterId'),
              reportedId: anyNamed('reportedId'),
              connectionId: anyNamed('connectionId'),
              reason: anyNamed('reason'),
              sealed: anyNamed('sealed'),
              verified: captureAnyNamed('verified'),
            ),
          ).captured.single
          as bool;
    }

    test('with nothing in it verifies nothing', () async {
      expect(await verified(const []), isFalse);
    });

    test('of what the reported person sent the reporter verifies', () async {
      expect(await verified([message(from: 'them', to: 'u1')]), isTrue);
    });

    test('of someone else\'s messages does not', () async {
      expect(await verified([message(from: 'a third person', to: 'someone')]), isFalse);
    });

    test('of only the reporter\'s own words does not', () async {
      expect(await verified([message(from: 'u1', to: 'them')]), isFalse);
    });

    test('about oneself does not', () async {
      expect(await verified([message(from: 'u1', to: 'them')], reportedId: 'u1'), isFalse);
    });

    test('with a key the sender made unreadable is filed, unverified', () async {
      expect(await verified([message(from: 'them', to: 'u1')..['key'] = 'not base64!']), isFalse);
    });

    test('has room for a message\'s words, and no more', () async {
      when(app.config.reportReviewKey).thenReturn(base64.encode(List.filled(32, 1)));
      when(app.config.messageTags).thenReturn(tags);
      final long = message(from: 'them', to: 'u1')..['words'] = 'x' * 16385;
      final res = await app.send(
        'POST',
        '/reports',
        body: {
          'reportedId': 'them',
          'reason': 'abuse',
          'messages': [long],
        },
      );
      expect(res.status, 400);

      final named = await app.send('POST', '/reports', body: {'reportedId': 'x' * 129, 'reason': 'abuse'});
      expect(named.status, 400);
    });
  });

  test('a report with a message that lacks its proof is refused', () async {
    when(app.config.reportReviewKey).thenReturn(base64.encode(List.filled(32, 1)));
    when(app.config.messageTags).thenReturn(MessageTags({'k': List.filled(32, 1)}));
    final res = await app.send(
      'POST',
      '/reports',
      body: {
        'reportedId': 'u',
        'reason': 'abuse',
        'messages': [
          {'words': 'hi'},
        ],
      },
    );
    expect(res.status, 400);
  });

  test('a note is ciphertext too', () async {
    final res = await app.send(
      'PUT',
      '/notes/$item',
      body: {
        'connectionId': thread,
        'content': {'text': 'hi'},
      },
    );
    expect(res.status, 400);
  });

  const connection = '01900000-0000-7000-8000-000000000003';

  ThreadItem stored({String? cursor}) => ThreadItem(
    id: item,
    threadId: thread,
    kind: 'message',
    content: 'sealed',
    commitment: commitment,
    tag: 't',
    tagKey: 'k',
    at: DateTime.utc(2026),
    createdAt: DateTime.utc(2026),
    cursor: cursor,
  );

  group('a thread', () {
    test('opens on a connection the caller is in', () async {
      when(
        app.db.openThread(userId: anyNamed('userId'), connectionId: anyNamed('connectionId')),
      ).thenAnswer((_) async => Thread(id: thread, connectionId: connection));

      final res = await app.send('POST', '/connections/$connection/thread');

      expect(res.status, 200);
      expect(Thread.fromJson(jsonDecode(res.body) as Map).id, thread);
      verify(app.db.openThread(userId: 'u1', connectionId: connection)).called(1);
    });

    test('doesn\'t open on a connection the caller isn\'t in, or that was never accepted', () async {
      when(
        app.db.openThread(userId: anyNamed('userId'), connectionId: anyNamed('connectionId')),
      ).thenAnswer((_) async => null);

      final res = await app.send('POST', '/connections/$connection/thread');

      expect(res.status, 404);
    });

    test('the inbox lists the caller\'s threads', () async {
      when(app.db.getThreads(userId: anyNamed('userId'))).thenAnswer((_) async => [Thread(id: thread, unread: 2)]);

      final res = await app.send('GET', '/threads');

      expect(res.status, 200);
      expect(ThreadList.fromJson(jsonDecode(res.body) as Map).threads.single.unread, 2);
      verify(app.db.getThreads(userId: 'u1')).called(1);
    });

    test('reads items after a cursor, about one subject, with the next cursor while there are more', () async {
      when(
        app.db.getThreadItems(
          userId: anyNamed('userId'),
          threadId: anyNamed('threadId'),
          since: anyNamed('since'),
          before: anyNamed('before'),
          subjectType: anyNamed('subjectType'),
          subjectId: anyNamed('subjectId'),
          limit: anyNamed('limit'),
        ),
      ).thenAnswer((_) async => Page(items: [stored(cursor: 'next')], hasMore: true));

      final res = await app.send('GET', '/threads/$thread/items?since=c1&subjectType=workout&subjectId=w1&limit=5');

      expect(res.status, 200);
      expect((jsonDecode(res.body) as Map)['cursor'], 'next');
      verify(
        app.db.getThreadItems(
          userId: 'u1',
          threadId: thread,
          since: 'c1',
          before: null,
          subjectType: 'workout',
          subjectId: 'w1',
          limit: 5,
        ),
      ).called(1);
    });

    for (final (what, query) in [
      ('both a since and a before', 'since=a&before=b'),
      ('a subject the database can\'t store', 'subjectType=workout&subjectId=w%00'),
    ]) {
      test('a read with $what is refused before the database sees it', () async {
        final res = await app.send('GET', '/threads/$thread/items?$query');
        expect(res.status, 400);
        verifyZeroInteractions(app.db);
      });
    }

    test('marking it read moves the caller\'s position to the cursor given', () async {
      when(
        app.db.markThreadRead(userId: anyNamed('userId'), threadId: anyNamed('threadId'), cursor: anyNamed('cursor')),
      ).thenAnswer((_) async {});

      final res = await app.send('PUT', '/threads/$thread/read', body: {'cursor': 'c9'});

      expect(res.status, 204);
      verify(app.db.markThreadRead(userId: 'u1', threadId: thread, cursor: 'c9')).called(1);
    });

    test('a message about a subject carries it as a reference', () async {
      when(app.config.messageTags).thenReturn(MessageTags({'k': List.filled(32, 1)}));
      when(app.config.eventsQueueUrl).thenReturn('https://sqs.test/events');
      when(app.events.publish(queueUrl: anyNamed('queueUrl'), message: anyNamed('message'))).thenAnswer((_) async {});
      when(
        app.db.getThreadParties(senderId: anyNamed('senderId'), threadId: anyNamed('threadId')),
      ).thenAnswer((_) async => (threadId: thread, senderId: 'u1', recipientId: 'them', connectionId: connection));
      when(
        app.db.addThreadItem(
          senderId: anyNamed('senderId'),
          threadId: anyNamed('threadId'),
          id: anyNamed('id'),
          kind: anyNamed('kind'),
          content: anyNamed('content'),
          commitment: anyNamed('commitment'),
          tag: anyNamed('tag'),
          tagKey: anyNamed('tagKey'),
          at: anyNamed('at'),
          createdAt: anyNamed('createdAt'),
          subjectType: anyNamed('subjectType'),
          subjectId: anyNamed('subjectId'),
        ),
      ).thenAnswer((_) async => (stored(), true));

      final res = await app.send(
        'POST',
        '/threads/$thread/items',
        body: {...body(), 'subjectType': 'workout', 'subjectId': 'w1'},
      );

      expect(res.status, 201);
      final captured = verify(
        app.db.addThreadItem(
          senderId: anyNamed('senderId'),
          threadId: anyNamed('threadId'),
          id: anyNamed('id'),
          kind: anyNamed('kind'),
          content: anyNamed('content'),
          commitment: anyNamed('commitment'),
          tag: anyNamed('tag'),
          tagKey: anyNamed('tagKey'),
          at: anyNamed('at'),
          createdAt: anyNamed('createdAt'),
          subjectType: captureAnyNamed('subjectType'),
          subjectId: captureAnyNamed('subjectId'),
        ),
      ).captured;
      expect(captured, ['workout', 'w1']);
    });

    test('a commitment that isn\'t base64 is refused as one', () async {
      final res = await app.send('POST', '/threads/$thread/items', body: body(commit: 'not base64!'));
      expect(res.status, 400);
      expect(res.body, contains('invalid_commitment'));
    });
  });

  group('notes', () {
    const note = '01900000-0000-7000-8000-000000000004';

    CoachNote saved() =>
        CoachNote(id: note, connectionId: connection, content: 'sealed', updatedAt: DateTime.utc(2026));

    test('a coach saves one on a client, as ciphertext', () async {
      when(
        app.db.saveNote(
          coachId: anyNamed('coachId'),
          id: anyNamed('id'),
          connectionId: anyNamed('connectionId'),
          content: anyNamed('content'),
        ),
      ).thenAnswer((_) async => saved());

      final res = await app.send('PUT', '/notes/$note', body: {'connectionId': connection, 'content': 'sealed'});

      expect(res.status, 200);
      verify(app.db.saveNote(coachId: 'u1', id: note, connectionId: connection, content: 'sealed')).called(1);
    });

    test('a coach lists them on one client, with the next cursor while there are more', () async {
      when(
        app.db.getNotes(
          coachId: anyNamed('coachId'),
          connectionId: anyNamed('connectionId'),
          cursor: anyNamed('cursor'),
          limit: anyNamed('limit'),
        ),
      ).thenAnswer((_) async => Page(items: [saved()], hasMore: true));

      final res = await app.send('GET', '/notes?connectionId=$connection&cursor=$note');

      expect(res.status, 200);
      expect((jsonDecode(res.body) as Map)['cursor'], note);
      verify(app.db.getNotes(coachId: 'u1', connectionId: connection, cursor: note, limit: 30)).called(1);
    });

    test('a coach deletes one, 204', () async {
      when(app.db.deleteNote(coachId: anyNamed('coachId'), id: anyNamed('id'))).thenAnswer((_) async {});

      final res = await app.send('DELETE', '/notes/$note');

      expect(res.status, 204);
      verify(app.db.deleteNote(coachId: 'u1', id: note)).called(1);
    });
  });

  test('a report names the connection it came from', () async {
    when(app.config.reportReviewKey).thenReturn(base64.encode(List.filled(32, 1)));
    when(app.config.messageTags).thenReturn(MessageTags({'k': List.filled(32, 1)}));
    when(
      app.db.fileReport(
        reporterId: anyNamed('reporterId'),
        reportedId: anyNamed('reportedId'),
        connectionId: anyNamed('connectionId'),
        reason: anyNamed('reason'),
        sealed: anyNamed('sealed'),
        verified: anyNamed('verified'),
      ),
    ).thenAnswer((_) async {});

    final res = await app.send(
      'POST',
      '/reports',
      body: {'reportedId': 'them', 'connectionId': connection, 'reason': 'abuse'},
    );

    expect(res.status, 204);
    verify(
      app.db.fileReport(
        reporterId: 'u1',
        reportedId: 'them',
        connectionId: connection,
        reason: 'abuse',
        sealed: anyNamed('sealed'),
        verified: false,
      ),
    ).called(1);
  });
}
