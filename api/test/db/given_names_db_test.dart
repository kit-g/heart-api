@Tags(['db'])
library;

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
    test('a coach sets, changes and clears a name', () async {
      final (coach, student, connection) = await coaching();
      expect((await seen(coach, connection))?.name, 'u_$student');
      expect((await seen(coach, connection))?.namedByYou, isFalse);

      expect(await h.db.nameClient(actorId: coach, connectionId: connection, name: 'Sam'), isTrue);
      expect((await seen(coach, connection))?.name, 'Sam');
      expect((await seen(coach, connection))?.namedByYou, isTrue);

      await h.db.nameClient(actorId: coach, connectionId: connection, name: 'Samantha');
      expect((await seen(coach, connection))?.name, 'Samantha');

      expect(await h.db.nameClient(actorId: coach, connectionId: connection), isTrue);
      expect((await seen(coach, connection))?.name, 'u_$student');
      expect((await seen(coach, connection))?.namedByYou, isFalse);

      expect(
        await h.db.nameClient(actorId: coach, connectionId: connection),
        isTrue,
        reason: 'nothing to clear',
      );
    });

    test('the default is the invitation\'s name, then the client\'s own', () async {
      final (coach, student, connection) = await coaching();
      await invited(coach, student, 'Sam from the gym');
      expect((await seen(coach, connection))?.name, 'Sam from the gym');
      expect((await seen(coach, connection))?.namedByYou, isTrue);

      await h.db.nameClient(actorId: coach, connectionId: connection, name: 'Sam');
      await h.db.nameClient(actorId: coach, connectionId: connection);
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

      expect(await h.db.nameClient(actorId: coach, connectionId: connection, name: 'Sam, before'), isTrue);
      final former = await h.db.getRoster(coachId: coach, former: true);
      expect(former.items.single.name, 'Sam, before');
      expect(former.items.single.namedByYou, isTrue);
    });

    test('only the coach, of someone who accepted, with no block between them', () async {
      final (coach, student, connection) = await coaching();
      expect(await h.db.nameClient(actorId: student, connectionId: connection, name: 'Coach'), isFalse);

      final stranger = await h.seedProfile();
      expect(await h.db.nameClient(actorId: stranger, connectionId: connection, name: 'Who'), isFalse);

      final (asked, _, pending) = await coaching(status: 'pending');
      await h.exec('UPDATE connections SET accepted_at = NULL WHERE id = @id::uuid', {'id': pending});
      expect(await h.db.nameClient(actorId: asked, connectionId: pending, name: 'Not yet'), isFalse);

      final (a, b) = (await h.seedProfile(), await h.seedProfile());
      final peers = await h.exec(
        '''
        INSERT INTO connections (initiator_id, target_id, initiator_role, target_role, domain, status, status_by, accepted_at)
        VALUES (@a, @b, 'PEER', 'PEER', 'fitness', 'active', @b, now())
        RETURNING id
        ''',
        {'a': a, 'b': b},
      );
      expect(await h.db.nameClient(actorId: a, connectionId: peers.first[0].toString(), name: 'Pal'), isFalse);

      await h.db.nameClient(actorId: coach, connectionId: connection, name: 'Sam');
      await h.exec('INSERT INTO blocks (blocker_id, blocked_id) VALUES (@s, @c)', {'s': student, 'c': coach});
      expect((await seen(coach, connection))?.name, isNull, reason: 'a block reads as an ending, without a name');
      expect(await h.db.nameClient(actorId: coach, connectionId: connection, name: 'Sam'), isFalse);
      expect(await h.db.nameClient(actorId: coach, connectionId: connection), isFalse);
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

    test('a push to the coach names the client as the coach does', () async {
      final (coach, student, connection) = await coaching();
      await h.db.nameClient(actorId: coach, connectionId: connection, name: 'Sam');

      final toCoach = await h.db.getPushAudience(userId: coach, topic: 'coaching.message', actorId: student);
      expect(toCoach.actorName, 'Sam');

      final toStudent = await h.db.getPushAudience(userId: student, topic: 'coaching.message', actorId: coach);
      expect(toStudent.actorName, 'u_$coach');
    });
  });

  test('goes with either account', () async {
    final (coach, student, connection) = await coaching();
    await h.db.nameClient(actorId: coach, connectionId: connection, name: 'Sam');
    await h.exec('DELETE FROM profiles WHERE id = @s', {'s': student});
    final left = await h.exec('SELECT count(*) FROM given_names WHERE giver_id = @c', {'c': coach});
    expect(left.single[0], 0);
  });
}

class _Harness extends DatabaseTestBase;
