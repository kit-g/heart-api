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
      final withdrawn = await h.db.previewInvitation(token: invitation.token!);
      expect(withdrawn?.good, isFalse);
      expect(withdrawn?.toMap().keys, ['good'], reason: 'a withdrawn link no longer says who made it');
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

      final connection = (await h.db.acceptInvitation(
        userId: student,
        token: invitation.token!,
        shares: {.goals},
      )).connection;
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

      final first = (await h.db.acceptInvitation(userId: student, token: invitation.token!)).connection;
      final second = (await h.db.acceptInvitation(
        userId: student,
        token: invitation.token!,
        shares: {.goals},
      )).connection;
      expect(second.connectionId, first.connectionId);
      expect(second.acceptedAt, first.acceptedAt);
      expect(second.shares, isEmpty);
    });

    test('says which accept made the connection', () async {
      final c = await coach();
      final student = await h.seedProfile();
      final invitation = await invite(c);

      expect((await h.db.acceptInvitation(userId: student, token: invitation.token!)).connected, isTrue);
      expect((await h.db.acceptInvitation(userId: student, token: invitation.token!)).connected, isFalse);
      expect(
        (await h.db.acceptInvitation(userId: student, token: (await invite(c)).token!)).connected,
        isFalse,
        reason: 'a second link from a coach already live connects nothing new',
      );

      await h.db.deleteConnection(actorId: c, targetId: student, role: .coach, domain: .fitness);
      expect((await h.db.acceptInvitation(userId: student, token: (await invite(c)).token!)).connected, isTrue);
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

      final connection = (await h.db.acceptInvitation(userId: student, token: invitation.token!)).connection;
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
      final first = (await h.db.acceptInvitation(
        userId: student,
        token: (await invite(c)).token!,
        shares: {.history},
      )).connection;
      await h.exec("UPDATE connections SET accepted_at = '2020-01-01Z' WHERE id = @id::uuid", {
        'id': first.connectionId,
      });
      await h.db.deleteConnection(actorId: c, targetId: student, role: .coach, domain: .fitness);

      final again = (await h.db.acceptInvitation(userId: student, token: (await invite(c)).token!)).connection;
      expect(again.connectionId, first.connectionId);
      expect(again.status, ConnectionStatus.active);
      expect(again.acceptedAt!.isAfter(DateTime.utc(2021)), isTrue);
      expect(again.shares, isEmpty);
    });

    test('a coach already live in the domain keeps what they have', () async {
      final c = await coach();
      final student = await h.seedProfile();
      final first = (await h.db.acceptInvitation(
        userId: student,
        token: (await invite(c)).token!,
        shares: {.goals},
      )).connection;
      final second = (await h.db.acceptInvitation(userId: student, token: (await invite(c)).token!)).connection;
      expect(second.acceptedAt, first.acceptedAt);
      expect(second.shares, ['goals']);
    });

    test('peers who become coach and student in that domain are rewritten', () async {
      final c = await coach();
      final student = await h.seedProfile();
      await h.seedConnection(initiator: student, target: c);

      final connection = (await h.db.acceptInvitation(userId: student, token: (await invite(c)).token!)).connection;
      expect(connection.role, ConnectionRole.student);
      expect((await h.db.getConnections(c)).single.role, ConnectionRole.coach);
    });
  });

  group('on the web', () {
    Future<String> newAccount() async {
      final id = h.uid('web');
      addTearDown(() => h.exec('DELETE FROM profiles WHERE id = @id', {'id': id}));
      return id;
    }

    test('someone with an account made a moment ago can accept, and "Your coach" is on', () async {
      final c = await coach();
      final person = await newAccount();

      final connection = (await h.db.acceptInvitation(
        userId: person,
        token: (await invite(c)).token!,
        email: 'new@test.local',
        name: 'New Person',
      )).connection;
      expect(connection.status, ConnectionStatus.active);

      final profile = await h.db.getProfile(person);
      expect(profile?.email, 'new@test.local');
      expect(profile?.displayName, 'New Person');
      final feature = (profile?.settings.extra['features'] as Map)['yourCoach'] as Map;
      expect(feature['on'], isTrue);
      expect(DateTime.tryParse(feature['at'] as String), isNotNull);
    });

    test('accepting keeps an existing profile, and the other features in it', () async {
      final c = await coach();
      final person = await h.seedProfile();
      await h.exec(
        '''UPDATE profiles SET settings = '{"unitSystem": "metric", "features": {"muscleMap": {"on": true}}}' WHERE id = @id''',
        {'id': person},
      );

      await h.db.acceptInvitation(userId: person, token: (await invite(c)).token!, email: 'x@y', name: 'Other');

      final profile = await h.db.getProfile(person);
      expect(profile?.displayName, 'u_$person', reason: 'nothing else about them moved');
      final features = profile?.settings.extra['features'] as Map;
      expect(features.keys, unorderedEquals(['muscleMap', 'yourCoach']));
    });

    test('accepting turns "Your coach" on and keeps the rest of what it holds', () async {
      final c = await coach();
      final person = await h.seedProfile();
      await h.exec(
        '''UPDATE profiles SET settings = '{"features": {"yourCoach": {"on": false, "without": ["x"], "later": 1}}}' WHERE id = @id''',
        {'id': person},
      );

      await h.db.acceptInvitation(userId: person, token: (await invite(c)).token!);

      final feature = ((await h.db.getProfile(person))?.settings.extra['features'] as Map)['yourCoach'] as Map;
      expect(feature['on'], isTrue);
      expect(feature['without'], ['x']);
      expect(feature['later'], 1);
    });

    test('someone new can decline or block too', () async {
      final c = await coach();
      final (one, two) = (await newAccount(), await newAccount());
      await h.db.declineInvitation(userId: one, token: (await invite(c)).token!, email: 'a@b', name: 'A');
      await h.db.blockInviter(userId: two, token: (await invite(c)).token!, email: 'c@d', name: 'C');
      expect((await h.db.getBlocks(userId: two)).items.single.id, c);
    });

    test('a link that is gone makes no profile', () async {
      final person = await newAccount();
      await expectLater(
        h.db.acceptInvitation(userId: person, token: TokenSecret.random(), email: 'a@b', name: 'A'),
        throwsA(isA<NotFound>()),
      );
      expect(await h.db.getProfile(person), isNull);
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
    expect(
      (await h.db.acceptInvitation(userId: other, token: renewed.token!)).connection.status,
      ConnectionStatus.active,
    );

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
    expect(
      (await h.db.acceptInvitation(userId: student, token: renewed.token!)).connection.status,
      ConnectionStatus.active,
    );

    await expectLater(
      h.db.renewInvitation(inviterId: c, invitationId: invitation.id, token: TokenSecret.random()),
      throwsA(isA<NotFound>()),
      reason: 'an accepted link is done',
    );
  });

  group('sending a link again', () {
    Future<Invitation> renew(String inviter, String invitationId) {
      return h.db.renewInvitation(inviterId: inviter, invitationId: invitationId, token: TokenSecret.random());
    }

    test('needs the entitlement, as making one does', () async {
      final c = await coach();
      final invitation = await invite(c);
      await h.exec('DELETE FROM entitlements WHERE user_id = @c', {'c': c});
      await expectLater(
        renew(c, invitation.id),
        throwsA(isA<Forbidden>().having((e) => e.code, 'code', 'coaching_beta')),
      );
    });

    test('stops at too many recent declines, as making one does', () async {
      final c = await coach();
      final declined = <Invitation>[];
      for (var i = 0; i < 20; i++) {
        final invitation = await invite(c);
        await h.db.declineInvitation(userId: await h.seedProfile(), token: invitation.token!);
        declined.add(invitation);
      }
      await expectLater(renew(c, declined.first.id), refusedWith('invitation_limit'));
    });

    test('a link already open does not count against itself', () async {
      final c = await coach();
      final invitation = await invite(c);
      await h.exec(
        '''
        INSERT INTO invitations (inviter_id, token_hash, name, expires_at)
        SELECT @c, decode(md5(@c || g::text), 'hex'), 'x', now() + INTERVAL '1 day'
        FROM generate_series(1, 49) g
        ''',
        {'c': c},
      );
      expect((await renew(c, invitation.id)).status, 'pending');
    });

    test('an accepted link stays used up, even when sent again as it was accepted', () async {
      final c = await coach();
      final (first, second) = (await h.seedProfile(), await h.seedProfile());
      final invitation = await invite(c);
      await h.db.acceptInvitation(userId: first, token: invitation.token!);

      // what a send that read the link just before the acceptance committed leaves behind
      final token = TokenSecret.random();
      await h.exec(
        "UPDATE invitations SET token_hash = @hash, renewed_at = now() + INTERVAL '1 second' WHERE id = @id::uuid",
        {'hash': TokenSecret.hash(token), 'id': invitation.id},
      );
      await expectLater(h.db.acceptInvitation(userId: second, token: token), refusedWith('invitation_gone'));
    });
  });

  group('answering', () {
    test('a link its person declined is not anyone else\'s to decline', () async {
      final c = await coach();
      final (person, other) = (await h.seedProfile(), await h.seedProfile());
      final invitation = await invite(c);
      await h.db.declineInvitation(userId: person, token: invitation.token!);
      await h.db.declineInvitation(userId: other, token: invitation.token!);

      final answered = await h.exec(
        'SELECT user_id FROM invitation_responses WHERE invitation_id = @id::uuid',
        {'id': invitation.id},
      );
      expect(answered.map((row) => row[0]), [person]);
    });

    test('a link that ended takes no answer, and makes no profile', () async {
      final c = await coach();
      final canceled = await invite(c);
      await h.db.cancelInvitation(inviterId: c, invitationId: canceled.id);
      final expired = await invite(c);
      await h.exec("UPDATE invitations SET expires_at = now() - INTERVAL '1 second' WHERE id = @id::uuid", {
        'id': expired.id,
      });

      final person = h.uid('web');
      addTearDown(() => h.exec('DELETE FROM profiles WHERE id = @id', {'id': person}));
      await h.db.declineInvitation(userId: person, token: canceled.token!, email: 'a@b', name: 'A');
      await h.db.declineInvitation(userId: person, token: expired.token!, email: 'a@b', name: 'A');

      final statuses = (await h.db.getInvitations(inviterId: c)).items.map((i) => i.status);
      expect(statuses, unorderedEquals(['canceled', 'expired']));
      expect(await h.db.getProfile(person), isNull);
    });

    test('a block from a link sent again reads as declined', () async {
      final c = await coach();
      final student = await h.seedProfile();
      final invitation = await invite(c);
      await h.db.declineInvitation(userId: student, token: invitation.token!);
      final renewed = await h.db.renewInvitation(
        inviterId: c,
        invitationId: invitation.id,
        token: TokenSecret.random(),
      );

      await h.db.blockInviter(userId: student, token: renewed.token!);
      expect((await h.db.getInvitations(inviterId: c)).items.single.status, 'declined');
    });

    test('declining or blocking your own link says so', () async {
      final c = await coach();
      final invitation = await invite(c);
      await expectLater(h.db.declineInvitation(userId: c, token: invitation.token!), refusedWith('own_invitation'));
      await expectLater(h.db.blockInviter(userId: c, token: invitation.token!), refusedWith('own_invitation'));
    });

    test('accepting again after the relationship ended is no longer good', () async {
      final c = await coach();
      final student = await h.seedProfile();
      final invitation = await invite(c);
      await h.db.acceptInvitation(userId: student, token: invitation.token!);
      await h.db.deleteConnection(actorId: student, targetId: c, role: .student, domain: .fitness);

      await expectLater(
        h.db.acceptInvitation(userId: student, token: invitation.token!),
        refusedWith('invitation_gone'),
      );
    });

    test('a link accepted while the two are already live is answered, and nobody else can use it', () async {
      final c = await coach();
      final (student, other) = (await h.seedProfile(), await h.seedProfile());
      await h.db.acceptInvitation(userId: student, token: (await invite(c)).token!);
      final second = await invite(c);
      await h.db.acceptInvitation(userId: student, token: second.token!);

      expect((await h.db.getInvitations(inviterId: c)).items.map((i) => i.status), ['accepted', 'accepted']);
      await expectLater(h.db.acceptInvitation(userId: other, token: second.token!), refusedWith('invitation_gone'));
    });

    test('a relationship started over a live row is in its history', () async {
      final c = await coach();
      final student = await h.seedProfile();
      await h.seedConnection(initiator: student, target: c);
      Future<int> events() async {
        final rows = await h.exec(
          '''
          SELECT count(*)::int FROM connection_events e JOIN connections x ON x.id = e.connection_id
          WHERE x.domain = 'fitness' AND @s IN (x.initiator_id, x.target_id)
          ''',
          {'s': student},
        );
        return rows.first[0]! as int;
      }

      final before = await events();
      await h.db.acceptInvitation(userId: student, token: (await invite(c)).token!);
      expect(await events(), before + 1);
    });

    test('a coach with as many clients as one can hold gets no more', () async {
      final c = await coach();
      addTearDown(() => h.exec("DELETE FROM profiles WHERE id LIKE @c || '-client-%'", {'c': c}));
      await h.exec(
        '''
        WITH _people AS (
          INSERT INTO profiles (id, username, email)
          SELECT @c || '-client-' || g, 'client', @c || g || '@test.local'
          FROM generate_series(1, 1000) g
          RETURNING id
        )
        INSERT INTO connections (initiator_id, target_id, initiator_role, target_role, domain, status)
        SELECT @c, id, 'COACH', 'STUDENT', 'fitness', 'active' FROM _people
        ''',
        {'c': c},
      );
      await expectLater(
        h.db.acceptInvitation(userId: await h.seedProfile(), token: (await invite(c)).token!),
        refusedWith('invitation_gone'),
      );
    });

    // The block is set while the acceptance is under way: whichever of the two
    // commits second has to see the other.
    test('a block set while someone accepts leaves nothing live', () async {
      final c = await coach();
      final student = await h.seedProfile();
      final invitation = await invite(c);

      final outcomes = await h.runBlocked<String>(
        hold: (tx) => tx.execute(
          Sql.named('INSERT INTO blocks (blocker_id, blocked_id) VALUES (@c, @s)'),
          parameters: {'c': c, 's': student},
        ),
        calls: [
          () => h.db
              .acceptInvitation(userId: student, token: invitation.token!)
              .then<String>((_) => 'accepted', onError: (Object e) => (e as BadRequest).code),
        ],
      );
      expect(outcomes, ['invitation_gone']);
      expect(await h.db.getConnections(student), isEmpty);
    });
  });

  group('pages', () {
    test('invitations come a page at a time, newest first', () async {
      final c = await coach();
      final made = [for (var i = 0; i < 3; i++) await invite(c)];

      final first = await h.db.getInvitations(inviterId: c, limit: 2);
      expect(first.items.map((i) => i.id), [made[2].id, made[1].id]);
      expect(first.hasMore, isTrue);

      final rest = await h.db.getInvitations(inviterId: c, cursor: first.items.last.id, limit: 2);
      expect(rest.items.map((i) => i.id), [made[0].id]);
      expect(rest.hasMore, isFalse);
    });

    test('blocks come a page at a time', () async {
      final blocker = await h.seedProfile();
      final blocked = [for (var i = 0; i < 3; i++) await h.seedProfile()];
      for (final person in blocked) {
        await h.exec('INSERT INTO blocks (blocker_id, blocked_id) VALUES (@b, @p)', {'b': blocker, 'p': person});
      }

      final first = await h.db.getBlocks(userId: blocker, limit: 2);
      expect(first.items, hasLength(2));
      expect(first.hasMore, isTrue);
      final rest = await h.db.getBlocks(userId: blocker, cursor: first.items.last.id, limit: 2);
      expect(rest.hasMore, isFalse);
      expect([...first.items, ...rest.items].map((b) => b.id), unorderedEquals(blocked));
    });
  });
}

class _Harness extends DatabaseTestBase;
