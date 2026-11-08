import 'dart:convert';

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

  test('an id that is no invitation\'s is a 404, and a cursor that is no page\'s a 400', () async {
    expect((await app.send('DELETE', '/invitations/abc')).status, 404);
    expect((await app.send('POST', '/invitations/abc/resend', body: {})).status, 404);
    expect((await app.send('GET', '/invitations?cursor=abc')).status, 400);
    verifyZeroInteractions(app.db);
  });

  const invitation = '01900000-0000-7000-8000-000000000010';

  Invitation sample({String id = invitation, String? token}) => Invitation(
    id: id,
    name: 'Alex',
    status: 'pending',
    role: 'COACH',
    domain: 'fitness',
    expiresAt: DateTime.utc(2026, 12),
    createdAt: DateTime.utc(2026, 11),
    token: token,
  );

  test('an invitation naming the coach\'s own program starts the client on it', () async {
    const program = '01900000-0000-7000-8000-000000000001';
    when(app.db.getCoachProgram(coachId: anyNamed('coachId'), id: anyNamed('id'))).thenAnswer(
      (_) async => CoachProgram(id: program, name: 'Plan', version: 1, updatedAt: DateTime.utc(2026)),
    );
    when(
      app.db.createInvitation(
        inviterId: anyNamed('inviterId'),
        name: anyNamed('name'),
        domain: anyNamed('domain'),
        token: anyNamed('token'),
      ),
    ).thenAnswer((_) async => sample());
    when(
      app.db.attachInvitationProgram(
        coachId: anyNamed('coachId'),
        invitationId: anyNamed('invitationId'),
        programId: anyNamed('programId'),
      ),
    ).thenAnswer((_) async {});

    final res = await app.send('POST', '/invitations', body: {'name': 'Alex', 'programId': program});

    expect(res.status, 201);
    verify(app.db.attachInvitationProgram(coachId: 'u1', invitationId: invitation, programId: program)).called(1);
  });

  test('lists the inviter\'s links, with a cursor while there are more', () async {
    when(
      app.db.getInvitations(inviterId: anyNamed('inviterId'), cursor: anyNamed('cursor'), limit: anyNamed('limit')),
    ).thenAnswer((_) async => Page(items: [sample()], hasMore: true));

    final res = await app.send('GET', '/invitations?cursor=$invitation&limit=1');

    expect(res.status, 200);
    final json = jsonDecode(res.body) as Map;
    expect(json['invitations'] as List, hasLength(1));
    expect(json['cursor'], invitation);
    verify(app.db.getInvitations(inviterId: 'u1', cursor: invitation, limit: 1)).called(1);
  });

  test('withdrawing a link is 204', () async {
    when(
      app.db.cancelInvitation(inviterId: anyNamed('inviterId'), invitationId: anyNamed('invitationId')),
    ).thenAnswer((_) async {});

    final res = await app.send('DELETE', '/invitations/$invitation');

    expect(res.status, 204);
    verify(app.db.cancelInvitation(inviterId: 'u1', invitationId: invitation)).called(1);
  });

  test('resending a link mints a new secret server-side', () async {
    when(
      app.db.renewInvitation(
        inviterId: anyNamed('inviterId'),
        invitationId: anyNamed('invitationId'),
        token: anyNamed('token'),
      ),
    ).thenAnswer((call) async => sample(token: call.namedArguments[#token] as String));

    final res = await app.send('POST', '/invitations/$invitation/resend', body: {});

    expect(res.status, 200);
    final token =
        verify(
              app.db.renewInvitation(inviterId: 'u1', invitationId: invitation, token: captureAnyNamed('token')),
            ).captured.single
            as String;
    expect(token, isNotEmpty);
    expect(res.body, contains(token));
  });

  test('declining a link says who declined, and is 204', () async {
    when(
      app.db.declineInvitation(
        userId: anyNamed('userId'),
        token: anyNamed('token'),
        email: anyNamed('email'),
        name: anyNamed('name'),
      ),
    ).thenAnswer((_) async {});

    final res = await app.send('POST', '/invitation-links/abc/decline', body: {});

    expect(res.status, 204);
    verify(app.db.declineInvitation(userId: 'u1', token: 'abc', email: null, name: 'Sam')).called(1);
  });

  test('blocking from a link says who blocked, and is 204', () async {
    when(
      app.db.blockInviter(
        userId: anyNamed('userId'),
        token: anyNamed('token'),
        email: anyNamed('email'),
        name: anyNamed('name'),
      ),
    ).thenAnswer((_) async {});

    final res = await app.send('POST', '/invitation-links/abc/block', body: {});

    expect(res.status, 204);
    verify(app.db.blockInviter(userId: 'u1', token: 'abc', email: null, name: 'Sam')).called(1);
  });

  test('lists who the caller blocked, and lifts a block', () async {
    when(
      app.db.getBlocks(userId: anyNamed('userId'), cursor: anyNamed('cursor'), limit: anyNamed('limit')),
    ).thenAnswer(
      (_) async => Page(
        items: [BlockedPerson(id: 'them', name: 'Them', since: DateTime.utc(2026, 11))],
        hasMore: true,
      ),
    );
    when(app.db.liftBlock(userId: anyNamed('userId'), blockedId: anyNamed('blockedId'))).thenAnswer((_) async {});

    final listed = await app.send('GET', '/blocks');
    expect(listed.status, 200);
    final json = jsonDecode(listed.body) as Map;
    expect((json['blocks'] as List).single, containsPair('id', 'them'));
    expect(json['cursor'], 'them');

    final lifted = await app.send('DELETE', '/blocks/them');
    expect(lifted.status, 204);
    verify(app.db.liftBlock(userId: 'u1', blockedId: 'them')).called(1);
  });
}
