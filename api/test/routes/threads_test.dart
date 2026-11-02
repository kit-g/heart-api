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

  test('posting through the real app tells the other person', () async {
    when(app.config.messageTags).thenReturn(MessageTags({'k': List.filled(32, 1)}));
    when(app.config.eventsQueueUrl).thenReturn('https://sqs.test/events');
    when(app.events.publish(queueUrl: anyNamed('queueUrl'), message: anyNamed('message'))).thenAnswer((_) async {});
    when(
      app.db.getThreadParties(senderId: anyNamed('senderId'), threadId: anyNamed('threadId')),
    ).thenAnswer((_) async => (threadId: thread, senderId: 'me', recipientId: 'them'));
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
        true,
      ),
    );

    final res = await app.send('POST', '/threads/$thread/items', body: body());
    expect(res.status, 201);
    final message =
        verify(app.events.publish(queueUrl: anyNamed('queueUrl'), message: captureAnyNamed('message'))).captured.single
            as Map;
    expect(message['userId'], 'them');
    expect(message.toString(), isNot(contains('sealed')));
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

    Future<bool> verified(List<Map<String, dynamic>> messages) async {
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
      await app.send('POST', '/reports', body: {'reportedId': 'them', 'reason': 'abuse', 'messages': messages});
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
}
