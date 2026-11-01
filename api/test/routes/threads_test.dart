import 'dart:convert';

import 'package:heart/notifications/sealing.dart';
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
