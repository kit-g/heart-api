import 'package:heart/models/errors.dart';
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

  test('accepting connects even when the program it names is gone by then', () async {
    const program = '01900000-0000-7000-8000-000000000001';
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
        connectionId: '01900000-0000-7000-8000-000000000002',
        role: .student,
        domain: .fitness,
        status: .active,
        createdAt: DateTime.utc(2026),
      ),
    );
    when(app.db.invitationProgram(token: anyNamed('token'))).thenAnswer((_) async => program);
    when(
      app.db.getCoachSendContext(
        coachId: anyNamed('coachId'),
        id: anyNamed('id'),
        connectionId: anyNamed('connectionId'),
      ),
    ).thenAnswer((_) async => null);
    when(app.config.eventsQueueUrl).thenReturn('https://sqs.test/events');
    when(app.events.publish(queueUrl: anyNamed('queueUrl'), message: anyNamed('message'))).thenAnswer((_) async {});

    final res = await app.send('POST', '/invitation-links/abc/accept', body: {});
    expect(res.status, 200);
    expect(res.body, contains('"programDelivered":false'));
  });

  test('an invitation naming a program that isn\'t the coach\'s is refused before it is made', () async {
    const program = '01900000-0000-7000-8000-000000000001';
    when(
      app.db.getCoachProgram(coachId: anyNamed('coachId'), id: anyNamed('id')),
    ).thenThrow(const NotFound(type: 'Library program', id: program));

    final res = await app.send('POST', '/invitations', body: {'name': 'Alex', 'programId': program});
    expect(res.status, 404);
    verifyNever(
      app.db.createInvitation(
        inviterId: anyNamed('inviterId'),
        name: anyNamed('name'),
        domain: anyNamed('domain'),
        token: anyNamed('token'),
      ),
    );
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
}
