import 'package:heart_models/heart_models.dart';
import 'package:mockito/mockito.dart';
import 'package:test/test.dart';

import '../helpers/app_harness.dart';

void main() {
  late AppHarness app;

  setUp(() async => app = await AppHarness.start());
  tearDown(() => app.stop());

  test('reading a link needs no sign-in', () async {
    when(
      app.db.previewInvitation(token: anyNamed('token')),
    ).thenAnswer((_) async => InvitationPreview(inviterName: 'Alex', good: true));

    final res = await app.send('GET', '/invitation-links/abc', token: null);
    expect(res.status, 200);
    expect(res.body, contains('Alex'));
  });

  test('a link that does not exist is a 404', () async {
    when(app.db.previewInvitation(token: anyNamed('token'))).thenAnswer((_) async => null);
    final res = await app.send('GET', '/invitation-links/abc', token: null);
    expect(res.status, 404);
  });

  for (final path in ['accept', 'decline', 'block']) {
    test('answering a link needs a sign-in: $path', () async {
      final res = await app.send('POST', '/invitation-links/abc/$path', token: null, body: {});
      expect(res.status, 401);
    });
  }

  test('accepting through the real app tells the inviter', () async {
    when(
      app.db.acceptInvitation(
        userId: anyNamed('userId'),
        token: anyNamed('token'),
        shares: anyNamed('shares'),
        email: anyNamed('email'),
        name: anyNamed('name'),
      ),
    ).thenAnswer(
      (_) async => Connection(
        targetId: 'coach-1',
        connectionId: 'c1',
        role: .student,
        domain: .fitness,
        status: .active,
        createdAt: DateTime.utc(2026),
      ),
    );
    when(app.db.invitationProgram(token: anyNamed('token'))).thenAnswer((_) async => null);
    when(app.config.eventsQueueUrl).thenReturn('https://sqs.test/events');
    when(app.events.publish(queueUrl: anyNamed('queueUrl'), message: anyNamed('message'))).thenAnswer((_) async {});

    final res = await app.send('POST', '/invitation-links/abc/accept', body: {});
    expect(res.status, 200);
    final message =
        verify(app.events.publish(queueUrl: anyNamed('queueUrl'), message: captureAnyNamed('message'))).captured.single
            as Map;
    expect(message['userId'], 'coach-1');
    expect(message['topic'], 'coaching.invitation_accepted');
  });

  test('making an invitation mints the token server-side', () async {
    when(
      app.db.createInvitation(
        inviterId: anyNamed('inviterId'),
        name: anyNamed('name'),
        domain: anyNamed('domain'),
        token: anyNamed('token'),
      ),
    ).thenAnswer(
      (call) async => Invitation(
        id: 'i',
        name: 'Alex',
        status: 'pending',
        role: 'COACH',
        domain: 'fitness',
        expiresAt: DateTime.utc(2026),
        createdAt: DateTime.utc(2026),
        token: call.namedArguments[#token] as String,
      ),
    );

    final res = await app.send('POST', '/invitations', body: {'name': 'Alex'});
    expect(res.status, 201);
    expect(res.body, contains('"token"'));
  });

  test('a name is required', () async {
    final res = await app.send('POST', '/invitations', body: {'name': ' '});
    expect(res.status, 400);
  });

  test('an id that is no invitation\'s is a 404, and a cursor that is no page\'s a 400', () async {
    expect((await app.send('DELETE', '/invitations/abc')).status, 404);
    expect((await app.send('POST', '/invitations/abc/resend', body: {})).status, 404);
    expect((await app.send('GET', '/invitations?cursor=abc')).status, 400);
    verifyZeroInteractions(app.db);
  });
}
