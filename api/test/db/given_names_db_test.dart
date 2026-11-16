@Tags(['db'])
library;

import 'package:heart/models/errors.dart';
import 'package:heart/models/program_copy.dart';
import 'package:heart_models/heart_models.dart';
import 'package:test/test.dart';

import 'db_test_utility.dart';

/// A coach's own name for a client (`given_names`, `_given_name`): who can give
/// one, and that every read of the coach's shows it while the client's don't.
void main() {
  final h = _Harness();

  setUpAll(h.setupDatabase);
  tearDownAll(h.teardownDatabase);

  Future<(String, String, String)> coaching({String status = 'active'}) async {
    final (coach, student) = (await h.seedProfile(), await h.seedProfile());
    final rows = await h.exec(
      '''
      INSERT INTO connections (initiator_id, target_id, initiator_role, target_role, domain, status, status_by, accepted_at)
      VALUES (@c, @s, 'COACH', 'STUDENT', 'fitness', @status, @c, now())
      RETURNING id
      ''',
      {'c': coach, 's': student, 'status': status},
    );
    return (coach, student, rows.first[0].toString());
  }

  Future<void> invited(String coach, String student, String name) async {
    await h.exec(
      '''
      WITH i AS (
        INSERT INTO invitations (inviter_id, token_hash, name, expires_at)
        VALUES (@c, decode(md5(random()::text), 'hex'), @n, now() + INTERVAL '1 day')
        RETURNING id
      )
      INSERT INTO invitation_responses (invitation_id, user_id, response)
      SELECT id, @s, 'accepted' FROM i
      ''',
      {'c': coach, 's': student, 'n': name},
    );
  }

  Future<Connection?> seen(String reader, String connection) {
    return h.db.getConnectionById(actorId: reader, connectionId: connection);
  }

  group('naming', () {
    test('a coach sets, changes and clears a name, each answered with the connection as read after', () async {
      final (coach, student, connection) = await coaching();
      expect((await seen(coach, connection))?.name, 'u_$student');
      expect((await seen(coach, connection))?.namedByYou, isFalse);

      final named = await h.db.nameClient(actorId: coach, connectionId: connection, name: 'Sam');
      expect((named?.name, named?.namedByYou, named?.connectionId), ('Sam', true, connection));
      expect((await seen(coach, connection))?.name, 'Sam');

      final renamed = await h.db.nameClient(actorId: coach, connectionId: connection, name: 'Samantha');
      expect(renamed?.name, 'Samantha');
      expect((await seen(coach, connection))?.name, 'Samantha');

      final cleared = await h.db.nameClient(actorId: coach, connectionId: connection);
      expect((cleared?.name, cleared?.namedByYou), ('u_$student', false));
      expect((await seen(coach, connection))?.name, 'u_$student');

      final again = await h.db.nameClient(actorId: coach, connectionId: connection);
      expect(again?.name, 'u_$student', reason: 'nothing to clear');
    });

    test('the default is the invitation\'s name, then the client\'s own', () async {
      final (coach, student, connection) = await coaching();
      await invited(coach, student, 'Sam from the gym');
      expect((await seen(coach, connection))?.name, 'Sam from the gym');
      expect((await seen(coach, connection))?.namedByYou, isTrue);

      await h.db.nameClient(actorId: coach, connectionId: connection, name: 'Sam');
      final cleared = await h.db.nameClient(actorId: coach, connectionId: connection);
      expect((cleared?.name, cleared?.namedByYou), ('Sam from the gym', true));
      expect((await seen(coach, connection))?.name, 'Sam from the gym');
    });

    test('the client never reads it', () async {
      final (coach, student, connection) = await coaching();
      await invited(coach, student, 'Sam from the gym');
      await h.db.nameClient(actorId: coach, connectionId: connection, name: 'Sam');

      final theirs = await seen(student, connection);
      expect(theirs?.name, 'u_$coach');
      expect(theirs?.namedByYou, isFalse);
      expect((await h.db.getConnections(student)).single.name, 'u_$coach');
    });

    test('a former client keeps it, and can still be named', () async {
      final (coach, student, connection) = await coaching();
      await h.db.nameClient(actorId: coach, connectionId: connection, name: 'Sam');
      await h.db.deleteConnection(actorId: student, targetId: coach, role: .student, domain: .fitness);
      expect((await seen(coach, connection))?.name, 'Sam');

      expect(
        (await h.db.nameClient(actorId: coach, connectionId: connection, name: 'Sam, before'))?.name,
        'Sam, before',
      );
      final former = await h.db.getRoster(coachId: coach, former: true);
      expect(former.items.single.name, 'Sam, before');
      expect(former.items.single.namedByYou, isTrue);
    });

    test('only the coach gives one, on a connection of theirs that was accepted', () async {
      final (coach, student, connection) = await coaching();
      await expectLater(
        h.db.nameClient(actorId: student, connectionId: connection, name: 'Coach'),
        throwsA(isA<Forbidden>()),
      );

      final stranger = await h.seedProfile();
      expect(await h.db.nameClient(actorId: stranger, connectionId: connection, name: 'Who'), isNull);

      final (asked, _, pending) = await coaching(status: 'pending');
      await h.exec('UPDATE connections SET accepted_at = NULL WHERE id = @id::uuid', {'id': pending});
      expect(await h.db.nameClient(actorId: asked, connectionId: pending, name: 'Not yet'), isNull);

      final (a, b) = (await h.seedProfile(), await h.seedProfile());
      final peers = await h.exec(
        '''
        INSERT INTO connections (initiator_id, target_id, initiator_role, target_role, domain, status, status_by, accepted_at)
        VALUES (@a, @b, 'PEER', 'PEER', 'fitness', 'active', @b, now())
        RETURNING id
        ''',
        {'a': a, 'b': b},
      );
      await expectLater(
        h.db.nameClient(actorId: a, connectionId: peers.first[0].toString(), name: 'Pal'),
        throwsA(isA<Forbidden>()),
      );
      expect(await h.db.nameClient(actorId: stranger, connectionId: connection), isNull);
    });

    test('a client who blocked the coach reads as an ending: the name is kept, and shown to nobody', () async {
      final (coach, student, connection) = await coaching();
      await h.exec('INSERT INTO blocks (blocker_id, blocked_id) VALUES (@s, @c)', {'s': student, 'c': coach});

      final named = await h.db.nameClient(actorId: coach, connectionId: connection, name: 'Sam');
      expect(named?.status, ConnectionStatus.severed);
      expect((named?.name, named?.namedByYou), (null, false));
      expect((await h.db.nameClient(actorId: coach, connectionId: connection))?.name, isNull);
    });

    test('a name given as a coach can be taken back after the roles turn', () async {
      final (a, b, connection) = await coaching();
      await h.db.nameClient(actorId: a, connectionId: connection, name: 'Bobby');
      await h.exec(
        '''
        UPDATE connections
        SET initiator_id = @b, target_id = @a
        WHERE id = @id::uuid
        ''',
        {'a': a, 'b': b, 'id': connection},
      );
      expect((await seen(a, connection))?.role, ConnectionRole.student);
      expect((await seen(a, connection))?.name, 'Bobby');

      final cleared = await h.db.nameClient(actorId: a, connectionId: connection);
      expect((cleared?.name, cleared?.namedByYou), ('u_$b', false));
    });
  });

  group('the coach\'s reads', () {
    test('roster and feed', () async {
      final (coach, student, connection) = await coaching();
      await h.exec(
        'INSERT INTO workouts (user_id, name, started_at, completed_at) VALUES (@u, @n, now(), now())',
        {'u': student, 'n': 'Trained'},
      );
      await h.db.nameClient(actorId: coach, connectionId: connection, name: 'Sam');

      final summary = (await h.db.getRoster(coachId: coach)).items.single;
      expect(summary.name, 'Sam');
      expect(summary.namedByYou, isTrue);

      final item = (await h.db.getCoachFeed(coachId: coach)).items.single;
      expect(item.name, 'Sam');
      expect(item.namedByYou, isTrue);
    });

    test('the inbox, from the coach\'s side only', () async {
      final (coach, student, connection) = await coaching();
      await h.db.nameClient(actorId: coach, connectionId: connection, name: 'Sam');
      await h.db.openThread(userId: coach, connectionId: connection);

      final mine = (await h.db.getThreads(userId: coach)).single;
      expect(mine.otherName, 'Sam');
      expect(mine.otherNamedByYou, isTrue);

      final theirs = (await h.db.getThreads(userId: student)).single;
      expect(theirs.otherName, 'u_$coach');
      expect(theirs.otherNamedByYou, isFalse);
    });

    test('who holds a program', () async {
      final (coach, student, connection) = await coaching();
      await h.db.nameClient(actorId: coach, connectionId: connection, name: 'Sam');
      final library = uuidV7();
      await h.db.saveCoachProgram(
        coachId: coach,
        id: library,
        name: 'One',
        body: withRowIds({
          'name': 'One',
          'sessions': [
            {'name': 'Monday', 'exercises': <Object?>[]},
          ],
        }),
      );
      await h.db.createProgramOrExisting(
        userId: student,
        program: Program(name: 'One'),
        sessions: const [],
        copy: (
          coachId: coach,
          connectionId: connection,
          libraryProgramId: library,
          libraryVersion: 1,
          libraryIds: const {},
          waits: false,
        ),
      );

      final holder = (await h.db.getCoachProgramHolders(coachId: coach, id: library)).single;
      expect(holder.studentName, 'Sam');
      expect(holder.studentNamedByYou, isTrue);
    });

    test('a push never carries it: what reaches Apple or Google is the client\'s own name', () async {
      final (coach, student, connection) = await coaching();
      await h.db.nameClient(actorId: coach, connectionId: connection, name: 'Sam, knee rehab');

      final toCoach = await h.db.getPushAudience(userId: coach, topic: 'coaching.message', actorId: student);
      expect(toCoach.actorName, 'u_$student');
    });

    test('the assistant, the shares, blocks and reactions name the client as the coach does', () async {
      final (coach, student, connection) = await coaching();
      await h.db.nameClient(actorId: coach, connectionId: connection, name: 'Sam');
      expect(await h.db.clientName(coachId: coach, clientId: student), 'Sam');
      expect(await h.db.clientName(coachId: student, clientId: coach), 'u_$coach');

      final template = await h.insertId(
        'INSERT INTO templates (user_id, name) VALUES (@u, @n) RETURNING id',
        {'u': coach, 'n': 'Push'},
      );
      await h.exec(
        '''
        INSERT INTO template_shares (coach_id, student_id, master_template_id, student_template_id)
        VALUES (@c, @s, @t::uuid, @t::uuid)
        ''',
        {'c': coach, 's': student, 't': template},
      );
      final shares = await h.db.getTemplateShares(userId: coach);
      expect(shares.items.single.assignedTo.name, 'Sam');

      await h.exec('INSERT INTO blocks (blocker_id, blocked_id) VALUES (@c, @s)', {'c': coach, 's': student});
      final blocked = await h.db.getBlocks(userId: coach);
      expect(blocked.items.single.name, 'Sam');
    });
  });

  test('goes with either account', () async {
    final (coach, student, connection) = await coaching();
    await h.db.nameClient(actorId: coach, connectionId: connection, name: 'Sam');
    await h.exec('DELETE FROM profiles WHERE id = @s', {'s': student});
    expect((await h.exec('SELECT count(*) FROM given_names WHERE giver_id = @c', {'c': coach})).single[0], 0);

    final (giver, person, other) = await coaching();
    await h.db.nameClient(actorId: giver, connectionId: other, name: 'Pat');
    await h.exec('DELETE FROM profiles WHERE id = @g', {'g': giver});
    expect((await h.exec('SELECT count(*) FROM given_names WHERE person_id = @p', {'p': person})).single[0], 0);
  });
}

class _Harness extends DatabaseTestBase;
