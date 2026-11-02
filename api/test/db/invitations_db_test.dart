@Tags(['db'])
library;

import 'package:heart/models/errors.dart';
import 'package:heart/models/tokens.dart';
import 'package:heart_models/heart_models.dart';
import 'package:postgres/postgres.dart' show Sql;
import 'package:test/test.dart';

import 'db_test_utility.dart';

void main() {
  final h = _Harness();

  setUpAll(h.setupDatabase);
  tearDownAll(h.teardownDatabase);

  Future<String> coach() async {
    final id = await h.seedProfile();
    await h.exec("INSERT INTO entitlements (user_id, entitlement) VALUES (@u, 'coach')", {'u': id});
    return id;
  }

  Future<Invitation> invite(String inviter, {String name = 'Alex'}) {
    return h.db.createInvitation(
      inviterId: inviter,
      name: name,
      domain: .fitness,
      token: TokenSecret.random(),
    );
  }

  Matcher refusedWith(String code) => throwsA(isA<BadRequest>().having((e) => e.code, 'code', code));

  group('createInvitation', () {
    test('needs the entitlement', () async {
      final stranger = await h.seedProfile();
      await expectLater(
        invite(stranger),
        throwsA(isA<Forbidden>().having((e) => e.code, 'code', 'coaching_beta')),
      );
    });

    test('answers the token once, and the store holds only its hash', () async {
      final c = await coach();
      final invitation = await invite(c);
      expect(invitation.status, 'pending');
      expect(invitation.token, isNotNull);

      final listed = (await h.db.getInvitations(inviterId: c)).items.single;
      expect(listed.id, invitation.id);
      expect(listed.token, isNull);
      expect(listed.status, 'pending');

      final stored = await h.exec(
        'SELECT token_hash FROM invitations WHERE id = @id::uuid',
        {'id': invitation.id},
      );
      expect(stored.first[0], TokenSecret.hash(invitation.token!));
    });

    test('stops at too many pending', () async {
      final c = await coach();
      await h.exec(
        '''
        INSERT INTO invitations (inviter_id, token_hash, name, expires_at)
        SELECT @c, decode(md5(@c || g::text), 'hex'), 'x', now() + INTERVAL '1 day'
        FROM generate_series(1, 50) g
        ''',
        {'c': c},
      );
      await expectLater(invite(c), refusedWith('invitation_limit'));
    });

    test('stops at too many recent declines, which an accepted one does not count towards', () async {
      final c = await coach();
      for (var i = 0; i < 20; i++) {
        final person = await h.seedProfile();
        final invitation = await invite(c);
        await h.db.declineInvitation(userId: person, token: invitation.token!);
      }
      await expectLater(invite(c), refusedWith('invitation_limit'));
    });
  });

  group('previewInvitation', () {
    test('says who is asking and whether the link is good', () async {
      final c = await coach();
      final invitation = await invite(c);

      final preview = await h.db.previewInvitation(token: invitation.token!);
      expect(preview?.good, isTrue);
      expect(preview?.inviterName, 'u_$c');
      expect(preview?.toMap().keys, unorderedEquals(['inviterName', 'good']), reason: 'nothing else');

      await h.db.cancelInvitation(inviterId: c, invitationId: invitation.id);
      expect((await h.db.previewInvitation(token: invitation.token!))?.good, isFalse);
    });

    test('is null for a link that does not exist', () async {
      expect(await h.db.previewInvitation(token: TokenSecret.random()), isNull);
    });

    test('opening it uses nothing up', () async {
      final c = await coach();
      final invitation = await invite(c);
      await h.db.previewInvitation(token: invitation.token!);
      await h.db.previewInvitation(token: invitation.token!);
      expect((await h.db.getInvitations(inviterId: c)).items.single.status, 'pending');
    });
  });

  group('acceptInvitation', () {
    test('starts a coach relationship, from now, with what the student shares', () async {
      final c = await coach();
      final student = await h.seedProfile();
      final invitation = await invite(c);

      final connection = await h.db.acceptInvitation(
        userId: student,
        token: invitation.token!,
        shares: {.goals},
      );
      expect(connection.targetId, c);
      expect(connection.role, ConnectionRole.student);
      expect(connection.status, ConnectionStatus.active);
      expect(connection.acceptedAt, isNotNull);
      expect(connection.shares, ['goals']);
      expect((await h.db.getInvitations(inviterId: c)).items.single.status, 'accepted');
    });

    test('twice is a no-op that answers the same relationship', () async {
      final c = await coach();
      final student = await h.seedProfile();
      final invitation = await invite(c);

      final first = await h.db.acceptInvitation(userId: student, token: invitation.token!);
      final second = await h.db.acceptInvitation(userId: student, token: invitation.token!, shares: {.goals});
      expect(second.connectionId, first.connectionId);
      expect(second.acceptedAt, first.acceptedAt);
      expect(second.shares, isEmpty);
    });

    // The statements have to overlap: both wait on a lock this test holds, so each
    // starts before the other has answered. One statement that took the lock itself
    // would still count answers from before it waited, and let both in.
    test('of two people waiting at once, one gets it', () async {
      final c = await coach();
      final people = [await h.seedProfile(), await h.seedProfile()];
      final invitation = await invite(c);

      late Future<List<String>> answers;
      await h.pool.runTx((tx) async {
        await tx.execute(
          Sql.named('SELECT id FROM invitations WHERE id = @id::uuid FOR UPDATE'),
          parameters: {'id': invitation.id},
        );
        answers = Future.wait([
          for (final person in people)
            h.db
                .acceptInvitation(userId: person, token: invitation.token!)
                .then<String>((_) => 'accepted', onError: (Object e) => (e as BadRequest).code),
        ]);
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });

      final outcomes = await answers;
      expect(outcomes.where((outcome) => outcome == 'accepted'), hasLength(1));
      expect(outcomes.where((outcome) => outcome == 'invitation_gone'), hasLength(1));
    });

    test('of two people racing, one gets it', () async {
      final c = await coach();
      final people = [await h.seedProfile(), await h.seedProfile(), await h.seedProfile()];
      final invitation = await invite(c);

      final outcomes = await Future.wait([
        for (final person in people)
          h.db
              .acceptInvitation(userId: person, token: invitation.token!)
              .then<String>((_) => 'accepted', onError: (Object e) => (e as BadRequest).code),
      ]);
      expect(outcomes.where((o) => o == 'accepted'), hasLength(1));
      expect(outcomes.where((o) => o == 'invitation_gone'), hasLength(2));
    });

    test('refuses your own link, one that ended, and an unknown one', () async {
      final c = await coach();
      final student = await h.seedProfile();
      final invitation = await invite(c);

      await expectLater(h.db.acceptInvitation(userId: c, token: invitation.token!), refusedWith('own_invitation'));
      await expectLater(
        h.db.acceptInvitation(userId: student, token: TokenSecret.random()),
        throwsA(isA<NotFound>()),
      );

      await h.db.cancelInvitation(inviterId: c, invitationId: invitation.id);
      await expectLater(
        h.db.acceptInvitation(userId: student, token: invitation.token!),
        refusedWith('invitation_gone'),
      );

      final expired = await invite(c);
      await h.exec("UPDATE invitations SET expires_at = now() - INTERVAL '1 second' WHERE id = @id::uuid", {
        'id': expired.id,
      });
      await expectLater(h.db.acceptInvitation(userId: student, token: expired.token!), refusedWith('invitation_gone'));
    });

    test('someone who declined can change their mind, and nobody else can step in', () async {
      final c = await coach();
      final (student, other) = (await h.seedProfile(), await h.seedProfile());
      final invitation = await invite(c);

      await h.db.declineInvitation(userId: student, token: invitation.token!);
      expect((await h.db.getInvitations(inviterId: c)).items.single.status, 'declined');
      await expectLater(h.db.acceptInvitation(userId: other, token: invitation.token!), refusedWith('invitation_gone'));

      final connection = await h.db.acceptInvitation(userId: student, token: invitation.token!);
      expect(connection.status, ConnectionStatus.active);
      expect((await h.db.getInvitations(inviterId: c)).items.single.status, 'accepted');
    });

    test('declining after accepting changes nothing', () async {
      final c = await coach();
      final student = await h.seedProfile();
      final invitation = await invite(c);
      await h.db.acceptInvitation(userId: student, token: invitation.token!);
      await h.db.declineInvitation(userId: student, token: invitation.token!);
      expect((await h.db.getInvitations(inviterId: c)).items.single.status, 'accepted');
    });

    test('a former client starts again from a new date, with nothing shared', () async {
      final c = await coach();
      final student = await h.seedProfile();
      final first = await h.db.acceptInvitation(
        userId: student,
        token: (await invite(c)).token!,
        shares: {.history},
      );
      await h.exec("UPDATE connections SET accepted_at = '2020-01-01Z' WHERE id = @id::uuid", {
        'id': first.connectionId,
      });
      await h.db.deleteConnection(actorId: c, targetId: student, role: .coach, domain: .fitness);

      final again = await h.db.acceptInvitation(userId: student, token: (await invite(c)).token!);
      expect(again.connectionId, first.connectionId);
      expect(again.status, ConnectionStatus.active);
      expect(again.acceptedAt!.isAfter(DateTime.utc(2021)), isTrue);
      expect(again.shares, isEmpty);
    });

    test('a coach already live in the domain keeps what they have', () async {
      final c = await coach();
      final student = await h.seedProfile();
      final first = await h.db.acceptInvitation(userId: student, token: (await invite(c)).token!, shares: {.goals});
      final second = await h.db.acceptInvitation(userId: student, token: (await invite(c)).token!);
      expect(second.acceptedAt, first.acceptedAt);
      expect(second.shares, ['goals']);
    });

    test('peers who become coach and student in that domain are rewritten', () async {
      final c = await coach();
      final student = await h.seedProfile();
      await h.seedConnection(initiator: student, target: c);

      final connection = await h.db.acceptInvitation(userId: student, token: (await invite(c)).token!);
      expect(connection.role, ConnectionRole.student);
      expect((await h.db.getConnections(c)).single.role, ConnectionRole.coach);
    });
  });

  group('blocking from a link', () {
    test('someone with no connection blocks the inviter, whose later links stop working for them', () async {
      final c = await coach();
      final student = await h.seedProfile();
      final invitation = await invite(c);

      await h.db.blockInviter(userId: student, token: invitation.token!);
      expect((await h.db.getBlocks(userId: student)).items.single.id, c);
      expect((await h.db.getInvitations(inviterId: c)).items.single.status, 'declined');

      final next = await invite(c);
      await expectLater(h.db.acceptInvitation(userId: student, token: next.token!), refusedWith('invitation_gone'));
    });

    test('a block from a link ends a live relationship, and lifting it gives nothing back', () async {
      final c = await coach();
      final student = await h.seedProfile();
      await h.db.acceptInvitation(userId: student, token: (await invite(c)).token!);

      await h.db.blockInviter(userId: student, token: (await invite(c)).token!);
      expect((await h.db.getConnections(student)).single.status, ConnectionStatus.severed);

      await h.db.liftBlock(userId: student, blockedId: c);
      expect((await h.db.getConnections(student)).single.status, ConnectionStatus.severed);
      expect(await h.db.areConnected(userA: c, userB: student), isFalse);
    });

    test('only the blocker lifts it, and a blocked row ends', () async {
      final c = await coach();
      final student = await h.seedProfile();
      await h.db.acceptInvitation(userId: student, token: (await invite(c)).token!);
      await h.db.changeConnectionStatus(
        actorId: student,
        targetId: c,
        role: .student,
        domain: .fitness,
        newStatus: .blocked,
      );

      await h.db.liftBlock(userId: c, blockedId: student);
      expect((await h.db.getBlocks(userId: student)).items, hasLength(1));

      await h.db.liftBlock(userId: student, blockedId: c);
      expect((await h.db.getBlocks(userId: student)).items, isEmpty);
      expect((await h.db.getConnections(student)).single.status, ConnectionStatus.severed);
    });
  });

  test('renewing a declined link opens it to the next person, and the decline still counts', () async {
    final c = await coach();
    final (declined, other) = (await h.seedProfile(), await h.seedProfile());
    final invitation = await invite(c);
    await h.db.declineInvitation(userId: declined, token: invitation.token!);
    expect((await h.db.getInvitations(inviterId: c)).items.single.status, 'declined');

    final renewed = await h.db.renewInvitation(
      inviterId: c,
      invitationId: invitation.id,
      token: TokenSecret.random(),
    );
    expect((await h.db.getInvitations(inviterId: c)).items.single.status, 'pending');
    expect((await h.db.acceptInvitation(userId: other, token: renewed.token!)).status, ConnectionStatus.active);

    final kept = await h.exec(
      "SELECT count(*) FROM invitation_responses WHERE invitation_id = @id::uuid AND response = 'declined'",
      {'id': invitation.id},
    );
    expect(kept.first[0], 1);
  });

  test('renewing gives a new token, and the old one stops working', () async {
    final c = await coach();
    final student = await h.seedProfile();
    final invitation = await invite(c);

    final renewed = await h.db.renewInvitation(
      inviterId: c,
      invitationId: invitation.id,
      token: TokenSecret.random(),
    );
    expect(renewed.token, isNot(invitation.token));
    expect(await h.db.previewInvitation(token: invitation.token!), isNull);
    expect((await h.db.acceptInvitation(userId: student, token: renewed.token!)).status, ConnectionStatus.active);

    await expectLater(
      h.db.renewInvitation(inviterId: c, invitationId: invitation.id, token: TokenSecret.random()),
      throwsA(isA<NotFound>()),
      reason: 'an accepted link is done',
    );
  });
}

class _Harness extends DatabaseTestBase;
