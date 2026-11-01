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
