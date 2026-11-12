@Tags(['db'])
library;

import 'package:heart/models/errors.dart';
import 'package:heart_models/heart_models.dart';
import 'package:postgres/postgres.dart' show Sql;
import 'package:test/test.dart';

import 'db_test_utility.dart';

/// Full integration coverage of the `ConnectionsService` query strings against a
/// live Postgres: create/read/list/status/delete plus the access-control and
/// error branches the SQL and mixin encode.
///
/// Connections are keyed on (initiator_id, target_id, domain) and read
/// bidirectionally, so each test seeds its own fresh profile pair to keep the
/// (mutable) connection rows isolated from sibling cases.
///
/// Tagged `db` — skipped by the default `dart test`. Run with:
///   dart test --run-skipped -t db
void main() {
  final h = _Harness();

  setUpAll(h.setupDatabase);
  tearDownAll(h.teardownDatabase);

  /// A fresh, connection-free pair of profiles for a single test.
  Future<(String, String)> pair() async {
    final a = await h.seedProfile();
    final b = await h.seedProfile();
    return (a, b);
  }

  group('createConnection', () {
    test('creates a pending connection and returns it from the initiator side', () async {
      final (a, b) = await pair();

      final c = await h.db.createConnection(
        initiatorId: a,
        targetId: b,
        role: ConnectionRole.peer,
        domain: ConnectionDomain.fitness,
      );

      expect(c.targetId, b);
      expect(c.role, ConnectionRole.peer);
      expect(c.domain, ConnectionDomain.fitness);
      expect(c.status, ConnectionStatus.pending); // DEFAULT 'pending'
    });

    test('stores reciprocal roles (coach → student) resolved per perspective', () async {
      final (coach, student) = await pair();

      final c = await h.db.createConnection(
        initiatorId: coach,
        targetId: student,
        role: ConnectionRole.coach,
        domain: ConnectionDomain.fitness,
      );
      expect(c.role, ConnectionRole.coach);

      // The target reads the reciprocal role.
      final fromStudent = await h.db.getConnection(
        actorId: student,
        targetId: coach,
        role: ConnectionRole.student,
        domain: ConnectionDomain.fitness,
      );
      expect(fromStudent?.role, ConnectionRole.student);
    });

    test('is idempotent — a repeat insert conflicts and returns the existing row', () async {
      final (a, b) = await pair();
      await h.db.createConnection(
        initiatorId: a,
        targetId: b,
        role: ConnectionRole.peer,
        domain: ConnectionDomain.fitness,
      );

      // ON CONFLICT DO NOTHING → the UNION ALL branch returns the existing row.
      final again = await h.db.createConnection(
        initiatorId: a,
        targetId: b,
        role: ConnectionRole.peer,
        domain: ConnectionDomain.fitness,
      );
      expect(again.targetId, b);
      expect(again.status, ConnectionStatus.pending);

      // Still exactly one connection, not a duplicate.
      final listed = await h.db.getConnections(a);
      expect(listed.where((c) => c.targetId == b), hasLength(1));
    });

    test('throws NotFound when the target profile does not exist', () async {
      final a = await h.seedProfile();
      await expectLater(
        h.db.createConnection(
          initiatorId: a,
          targetId: h.uid('ghost'),
          role: ConnectionRole.peer,
          domain: ConnectionDomain.fitness,
        ),
        throwsA(isA<NotFound>()),
      );
    });
  });

  group('getConnections', () {
    test('reads the connection from both the initiator and the target side', () async {
      final (coach, student) = await pair();
      await h.db.createConnection(
        initiatorId: coach,
        targetId: student,
        role: ConnectionRole.coach,
        domain: ConnectionDomain.fitness,
      );

      final forCoach = (await h.db.getConnections(coach)).toList();
      expect(forCoach, hasLength(1));
      expect(forCoach.single.targetId, student);
      expect(forCoach.single.role, ConnectionRole.coach);

      final forStudent = (await h.db.getConnections(student)).toList();
      expect(forStudent, hasLength(1));
      expect(forStudent.single.targetId, coach);
      expect(forStudent.single.role, ConnectionRole.student); // reciprocal
    });

    test('says who the other person is now, unless they blocked the reader', () async {
      final (coach, student) = await pair();
      await h.db.createConnection(initiatorId: coach, targetId: student, role: .peer, domain: .fitness);
      final id = (await h.db.getConnections(coach)).single.connectionId!;
      await h.exec("UPDATE connections SET status = 'active', accepted_at = now() WHERE id = @id::uuid", {'id': id});
      await h.exec("UPDATE profiles SET username = 'Coach Dana', avatar_url = 'https://a/d.jpg' WHERE id = @c", {
        'c': coach,
      });

      final seen = (await h.db.getConnections(student)).single;
      expect((seen.name, seen.avatar), ('Coach Dana', 'https://a/d.jpg'));
      expect((await h.db.getConnectionById(actorId: student, connectionId: id))?.name, 'Coach Dana');
      expect((await h.db.getConnections(coach)).single.name, 'u_$student');

      await h.db.changeConnectionStatus(
        actorId: coach,
        targetId: student,
        role: .peer,
        domain: .fitness,
        newStatus: .blocked,
      );
      final blocked = (await h.db.getConnections(student)).single;
      expect((blocked.name, blocked.avatar), (null, null));
      expect(blocked.status, ConnectionStatus.severed, reason: 'the one blocked sees an ended connection');
      expect((await h.db.getConnectionById(actorId: student, connectionId: id))?.name, isNull);
      final blocker = (await h.db.getConnections(coach)).single;
      expect((blocker.name, blocker.status), ('u_$student', ConnectionStatus.blocked));

      await h.exec('UPDATE blocks SET lifted_at = now() WHERE blocker_id = @c', {'c': coach});
      expect((await h.db.getConnections(student)).single.name, 'Coach Dana', reason: 'a lifted block hides nothing');
    });

    test('a request nobody accepted names the one who asked, not the one asked', () async {
      final (asker, asked) = await pair();
      await h.db.createConnection(initiatorId: asker, targetId: asked, role: .peer, domain: .fitness);

      expect((await h.db.getConnections(asker)).single.name, isNull, reason: 'asking reveals nobody');
      expect((await h.db.getConnections(asked)).single.name, 'u_$asker');

      await h.db.changeConnectionStatus(
        actorId: asked,
        targetId: asker,
        role: .peer,
        domain: .fitness,
        newStatus: .declined,
      );
      expect((await h.db.getConnections(asker)).single.name, isNull, reason: 'nor does being declined');
    });

    test('a blank name is no name', () async {
      final (a, b) = await pair();
      await h.db.createConnection(initiatorId: a, targetId: b, role: .peer, domain: .fitness);
      await h.exec("UPDATE profiles SET username = '  ' WHERE id = @a", {'a': a});
      expect((await h.db.getConnections(b)).single.name, isNull);
    });

    test('filters by role, matching the requester side of each connection', () async {
      final owner = await h.seedProfile();
      final peerTarget = await h.seedProfile();
      final studentTarget = await h.seedProfile();

      await h.db.createConnection(
        initiatorId: owner,
        targetId: peerTarget,
        role: ConnectionRole.peer,
        domain: ConnectionDomain.fitness,
      );
      await h.db.createConnection(
        initiatorId: owner,
        targetId: studentTarget,
        role: ConnectionRole.coach,
        domain: ConnectionDomain.fitness,
      );

      final coaches = (await h.db.getConnections(owner, roleFilter: ConnectionRole.coach)).toList();
      expect(coaches, hasLength(1));
      expect(coaches.single.targetId, studentTarget);

      final peers = (await h.db.getConnections(owner, roleFilter: ConnectionRole.peer)).toList();
      expect(peers, hasLength(1));
      expect(peers.single.targetId, peerTarget);
    });

    test('returns an empty iterable when the user has no connections', () async {
      final loner = await h.seedProfile();
      expect(await h.db.getConnections(loner), isEmpty);
    });
  });

  group('getConnection', () {
    test('returns the connection from the initiator perspective', () async {
      final (a, b) = await pair();
      await h.db.createConnection(
        initiatorId: a,
        targetId: b,
        role: ConnectionRole.peer,
        domain: ConnectionDomain.fitness,
      );

      final c = await h.db.getConnection(
        actorId: a,
        targetId: b,
        role: ConnectionRole.peer,
        domain: ConnectionDomain.fitness,
      );
      expect(c, isNotNull);
      expect(c!.targetId, b);
      expect(c.role, ConnectionRole.peer);
    });

    test('by its id, from either side, and to nobody else', () async {
      final (a, b) = await pair();
      await h.db.createConnection(initiatorId: a, targetId: b, role: .peer, domain: .fitness);
      final id = (await h.db.getConnections(a)).single.connectionId!;

      expect((await h.db.getConnectionById(actorId: a, connectionId: id))?.targetId, b);
      expect((await h.db.getConnectionById(actorId: b, connectionId: id))?.targetId, a);
      expect(await h.db.getConnectionById(actorId: await h.seedProfile(), connectionId: id), isNull);
      expect(await h.db.getConnectionById(actorId: a, connectionId: uuidV7()), isNull);
    });

    test('returns null when no connection matches', () async {
      final (a, b) = await pair(); // never connected
      final c = await h.db.getConnection(
        actorId: a,
        targetId: b,
        role: ConnectionRole.peer,
        domain: ConnectionDomain.fitness,
      );
      expect(c, isNull);
    });

    test('returns null when the role does not match the stored role', () async {
      final (coach, student) = await pair();
      await h.db.createConnection(
        initiatorId: coach,
        targetId: student,
        role: ConnectionRole.coach,
        domain: ConnectionDomain.fitness,
      );

      // Stored initiator_role is COACH, so a PEER lookup finds nothing.
      final c = await h.db.getConnection(
        actorId: coach,
        targetId: student,
        role: ConnectionRole.peer,
        domain: ConnectionDomain.fitness,
      );
      expect(c, isNull);
    });
  });

  group('deleteConnection', () {
    test('ends the connection and keeps the row, for both sides', () async {
      final (a, b) = await pair();
      await h.db.createConnection(
        initiatorId: a,
        targetId: b,
        role: ConnectionRole.peer,
        domain: ConnectionDomain.fitness,
      );

      await h.db.deleteConnection(
        actorId: a,
        targetId: b,
        role: ConnectionRole.peer,
        domain: ConnectionDomain.fitness,
      );

      final seenByA = await h.db.getConnection(
        actorId: a,
        targetId: b,
        role: ConnectionRole.peer,
        domain: ConnectionDomain.fitness,
      );
      expect(seenByA?.status, ConnectionStatus.severed);
      expect((await h.db.getConnections(b)).single.status, ConnectionStatus.severed);
      expect(await h.db.areConnected(userA: a, userB: b), isFalse);
    });

    test('deletes regardless of which side is named as initiator', () async {
      final (a, b) = await pair();
      await h.db.createConnection(
        initiatorId: a,
        targetId: b,
        role: ConnectionRole.peer,
        domain: ConnectionDomain.fitness,
      );

      // Addressed from the target's perspective, it still ends the pair's row.
      await h.db.deleteConnection(
        actorId: b,
        targetId: a,
        role: ConnectionRole.peer,
        domain: ConnectionDomain.fitness,
      );
      expect((await h.db.getConnections(a)).single.status, ConnectionStatus.severed);
    });

    test('is a no-op when there is no connection', () async {
      final (a, b) = await pair();
      await h.db.deleteConnection(
        actorId: a,
        targetId: b,
        role: ConnectionRole.peer,
        domain: ConnectionDomain.fitness,
      );
      expect(await h.db.getConnections(a), isEmpty);
    });

    // A hard delete makes the pair re-requestable, so letting the blocked party
    // delete the row is letting them unblock themselves.
    test('the blocked party cannot delete the block away', () async {
      final (blocker, blocked) = await pair();
      await h.seedConnection(initiator: blocked, target: blocker);
      await h.db.changeConnectionStatus(
        actorId: blocker,
        targetId: blocked,
        role: ConnectionRole.peer,
        domain: ConnectionDomain.fitness,
        newStatus: ConnectionStatus.blocked,
      );

      await expectLater(
        h.db.deleteConnection(
          actorId: blocked,
          targetId: blocker,
          role: ConnectionRole.peer,
          domain: ConnectionDomain.fitness,
        ),
        throwsA(isA<Forbidden>()),
      );
      expect(await h.db.getConnections(blocker), hasLength(1));
    });

    test('the blocker can end their own block, which lifts it', () async {
      final (blocker, blocked) = await pair();
      await h.seedConnection(initiator: blocked, target: blocker);
      await h.db.changeConnectionStatus(
        actorId: blocker,
        targetId: blocked,
        role: ConnectionRole.peer,
        domain: ConnectionDomain.fitness,
        newStatus: ConnectionStatus.blocked,
      );

      await h.db.deleteConnection(
        actorId: blocker,
        targetId: blocked,
        role: ConnectionRole.peer,
        domain: ConnectionDomain.fitness,
      );
      expect((await h.db.getConnections(blocker)).single.status, ConnectionStatus.severed);
      final live = await h.exec(
        'SELECT 1 FROM blocks WHERE blocker_id = @b AND lifted_at IS NULL',
        {'b': blocker},
      );
      expect(live, isEmpty);
    });
  });

  group('vocabulary guards', () {
    test('a self-connection is rejected by connections_no_self_check', () async {
      final a = await h.seedProfile();
      await expectLater(
        h.db.createConnection(
          initiatorId: a,
          targetId: a,
          role: ConnectionRole.coach,
          domain: ConnectionDomain.fitness,
        ),
        // Named rather than `anything`, so a different failure cannot pass this.
        throwsA(predicate((e) => '$e'.contains('connections_no_self_check'))),
      );
    });

    for (final (label, parse) in <(String, void Function())>[
      ('role', () => ConnectionRole.fromString('sensei')),
      ('domain', () => ConnectionDomain.fromString('yoga')),
      ('status', () => ConnectionStatus.fromString('nonsense')),
    ]) {
      test('an unknown $label throws instead of coercing to a default', () {
        expect(parse, throwsArgumentError);
      });
    }

    // Deliberately unconstrained in the schema: domain is a partition label the
    // code never branches on, so adding an activity should not need a migration.
    // The enum is what keeps unknown values out on the way in.
    test('the database accepts a domain the enum does not yet know', () async {
      final (a, b) = await pair();
      await h.exec(
        'INSERT INTO connections (initiator_id, target_id, initiator_role, target_role, domain) '
        "VALUES (@a, @b, 'PEER', 'PEER', 'cycling')",
        {'a': a, 'b': b},
      );
      final count = await h.exec(
        "SELECT 1 FROM connections WHERE initiator_id = @a AND domain = 'cycling'",
        {'a': a},
      );
      expect(count, hasLength(1));
    });
  });

  group('status_by', () {
    test('creating a connection records the initiator as having set it', () async {
      final (a, b) = await pair();
      await h.db.createConnection(
        initiatorId: a,
        targetId: b,
        role: ConnectionRole.peer,
        domain: ConnectionDomain.fitness,
      );

      final rows = await h.exec('SELECT status_by FROM connections WHERE initiator_id = @a', {'a': a});
      expect(rows.first.toColumnMap()['status_by'], a);
    });

    test('a status change records who made it', () async {
      final (a, b) = await pair();
      await h.db.createConnection(
        initiatorId: a,
        targetId: b,
        role: ConnectionRole.peer,
        domain: ConnectionDomain.fitness,
      );
      await h.db.changeConnectionStatus(
        actorId: b,
        targetId: a,
        role: ConnectionRole.peer,
        domain: ConnectionDomain.fitness,
        newStatus: ConnectionStatus.active,
      );

      final rows = await h.exec('SELECT status_by FROM connections WHERE initiator_id = @a', {'a': a});
      expect(rows.first.toColumnMap()['status_by'], b, reason: 'b accepted, so b set the status');
    });
  });

  group('changeConnectionStatus', () {
    test('the person who received the request can accept it', () async {
      final (a, b) = await pair();
      await h.db.createConnection(
        initiatorId: a,
        targetId: b,
        role: ConnectionRole.peer,
        domain: ConnectionDomain.fitness,
      );

      // `b` received it, so `b` accepts. From b's side `a` is the target.
      final updated = await h.db.changeConnectionStatus(
        actorId: b,
        targetId: a,
        role: ConnectionRole.peer,
        domain: ConnectionDomain.fitness,
        newStatus: ConnectionStatus.active,
      );
      expect(updated.status, ConnectionStatus.active);

      // Persisted, and now visible as an active connection.
      final reread = await h.db.getConnection(
        actorId: a,
        targetId: b,
        role: ConnectionRole.peer,
        domain: ConnectionDomain.fitness,
      );
      expect(reread?.status, ConnectionStatus.active);
      expect(await h.db.areConnected(userA: a, userB: b), isTrue);
    });

    // Before this guard, whoever sent a request could turn it active themselves —
    // which, with the workouts gate, meant a stranger reading your history.
    for (final outcome in [ConnectionStatus.active, ConnectionStatus.declined]) {
      test('the author of a request cannot ${outcome.name} it themselves', () async {
        final (a, b) = await pair();
        await h.db.createConnection(
          initiatorId: a,
          targetId: b,
          role: ConnectionRole.peer,
          domain: ConnectionDomain.fitness,
        );

        await expectLater(
          h.db.changeConnectionStatus(
            actorId: a,
            targetId: b,
            role: ConnectionRole.peer,
            domain: ConnectionDomain.fitness,
            newStatus: outcome,
          ),
          throwsA(isA<Forbidden>()),
        );

        expect(await h.db.areConnected(userA: a, userB: b), isFalse);
      });
    }

    test('either party may pause an active connection', () async {
      final (a, b) = await pair();
      await h.seedConnection(initiator: a, target: b);

      final paused = await h.db.changeConnectionStatus(
        actorId: a,
        targetId: b,
        role: ConnectionRole.peer,
        domain: ConnectionDomain.fitness,
        newStatus: ConnectionStatus.paused,
      );
      expect(paused.status, ConnectionStatus.paused);

      // …and either party may resume it, including the one who did not pause.
      final resumed = await h.db.changeConnectionStatus(
        actorId: b,
        targetId: a,
        role: ConnectionRole.peer,
        domain: ConnectionDomain.fitness,
        newStatus: ConnectionStatus.active,
      );
      expect(resumed.status, ConnectionStatus.active);
    });

    test('only the person who blocked can lift the block', () async {
      final (blocker, blocked) = await pair();
      await h.seedConnection(initiator: blocked, target: blocker);
      await h.db.changeConnectionStatus(
        actorId: blocker,
        targetId: blocked,
        role: ConnectionRole.peer,
        domain: ConnectionDomain.fitness,
        newStatus: ConnectionStatus.blocked,
      );

      await expectLater(
        h.db.changeConnectionStatus(
          actorId: blocked,
          targetId: blocker,
          role: ConnectionRole.peer,
          domain: ConnectionDomain.fitness,
          newStatus: ConnectionStatus.severed,
        ),
        throwsA(isA<Forbidden>()),
      );

      final lifted = await h.db.changeConnectionStatus(
        actorId: blocker,
        targetId: blocked,
        role: ConnectionRole.peer,
        domain: ConnectionDomain.fitness,
        newStatus: ConnectionStatus.severed,
      );
      expect(lifted.status, ConnectionStatus.severed);
    });

    // `changeConnectionStatus` reads the status, then writes. Without the
    // `AND status = @expectedStatus` clause on the UPDATE, two callers that both
    // read `pending` would both go on to write, and both would report success.
    // The invariant holds under any interleaving: exactly one attempt wins.
    test('concurrent transitions cannot both win', () async {
      final (a, b) = await pair();
      await h.db.createConnection(
        initiatorId: a,
        targetId: b,
        role: ConnectionRole.peer,
        domain: ConnectionDomain.fitness,
      );

      final outcomes = await h.runBlocked(
        hold: (tx) async {
          await tx.execute(
            Sql.named('SELECT 1 FROM connections WHERE initiator_id = @a AND target_id = @b FOR UPDATE'),
            parameters: {'a': a, 'b': b},
          );
        },
        calls: [
          for (var i = 0; i < 2; i++)
            () async {
              try {
                await h.db.changeConnectionStatus(
                  actorId: b,
                  targetId: a,
                  role: ConnectionRole.peer,
                  domain: ConnectionDomain.fitness,
                  newStatus: ConnectionStatus.active,
                );
                return true;
              } on Forbidden catch (error) {
                expect(error.code, 'forbidden');
                return false;
              }
            },
        ],
      );

      expect(outcomes.where((won) => won), hasLength(1));
      expect(outcomes.where((won) => !won), hasLength(1));

      final settled = await h.db.getConnection(
        actorId: a,
        targetId: b,
        role: ConnectionRole.peer,
        domain: ConnectionDomain.fitness,
      );
      expect(settled?.status, ConnectionStatus.active);
    });

    test('throws StateError when there is no connection to update', () async {
      final (a, b) = await pair();
      await expectLater(
        h.db.changeConnectionStatus(
          actorId: a,
          targetId: b,
          role: ConnectionRole.peer,
          domain: ConnectionDomain.fitness,
          newStatus: ConnectionStatus.active,
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('throws StateError on an illegal transition (pending → severed)', () async {
      final (a, b) = await pair();
      await h.db.createConnection(
        initiatorId: a,
        targetId: b,
        role: ConnectionRole.peer,
        domain: ConnectionDomain.fitness,
      );

      await expectLater(
        h.db.changeConnectionStatus(
          actorId: a,
          targetId: b,
          role: ConnectionRole.peer,
          domain: ConnectionDomain.fitness,
          newStatus: ConnectionStatus.severed,
        ),
        throwsA(isA<StateError>()),
      );

      // Left untouched.
      final unchanged = await h.db.getConnection(
        actorId: a,
        targetId: b,
        role: ConnectionRole.peer,
        domain: ConnectionDomain.fitness,
      );
      expect(unchanged?.status, ConnectionStatus.pending);
    });
  });

  group('areConnected', () {
    test('is true (both directions) once an active connection exists', () async {
      final (a, b) = await pair();
      await h.seedConnection(initiator: a, target: b); // seeds status 'active'

      expect(await h.db.areConnected(userA: a, userB: b), isTrue);
      expect(await h.db.areConnected(userA: b, userB: a), isTrue);
    });

    test('is false when the users are not connected', () async {
      final (a, b) = await pair();
      expect(await h.db.areConnected(userA: a, userB: b), isFalse);
    });

    test('is false when the connection exists but is not active (pending)', () async {
      final (a, b) = await pair();
      await h.db.createConnection(
        initiatorId: a,
        targetId: b,
        role: ConnectionRole.peer,
        domain: ConnectionDomain.fitness,
      ); // pending, not active

      expect(await h.db.areConnected(userA: a, userB: b), isFalse);
    });
  });

  group('the edges of a relationship', () {
    Future<Connection> ask(String from, String to) {
      return h.db.createConnection(initiatorId: from, targetId: to, role: .peer, domain: .fitness);
    }

    Future<Connection> move(String actor, String other, ConnectionStatus to) {
      return h.db.changeConnectionStatus(actorId: actor, targetId: other, role: .peer, domain: .fitness, newStatus: to);
    }

    test('ending what already ended leaves it as it ended, by whom', () async {
      final (a, b) = await pair();
      await ask(a, b);
      await move(b, a, .active);
      await h.db.deleteConnection(actorId: a, targetId: b, role: .peer, domain: .fitness);
      await h.db.deleteConnection(actorId: b, targetId: a, role: .peer, domain: .fitness);

      final row = await h.exec('SELECT status, status_by FROM connections WHERE initiator_id = @a', {'a': a});
      expect(row.first.toColumnMap(), {'status': 'severed', 'status_by': a});
    });

    test('asked again after an ending, it is accepted again when answered', () async {
      final (a, b) = await pair();
      await ask(a, b);
      await move(b, a, .active);
      await h.exec("UPDATE connections SET accepted_at = '2020-01-01Z' WHERE initiator_id = @a", {'a': a});
      await h.db.deleteConnection(actorId: a, targetId: b, role: .peer, domain: .fitness);

      final again = await ask(a, b);
      expect(again.status, ConnectionStatus.pending);
      expect(again.acceptedAt, isNull);
      expect((await move(b, a, .active)).acceptedAt!.isAfter(DateTime.utc(2021)), isTrue);
    });

    test('two people asking each other at once both get the one row', () async {
      final (a, b) = await pair();
      final answers = await h.runBlocked<Connection>(
        hold: (tx) => tx.execute(
          Sql.named(
            'INSERT INTO connections (initiator_id, target_id, initiator_role, target_role, domain, status_by) '
            "VALUES (@a, @b, 'PEER', 'PEER', 'fitness', @a)",
          ),
          parameters: {'a': a, 'b': b},
        ),
        calls: [() => ask(b, a)],
      );
      expect(answers.single.targetId, a);
      expect(answers.single.status, ConnectionStatus.pending);
    });

    test('nothing starts again while a block stands', () async {
      final (a, b) = await pair();
      await ask(a, b);
      await h.seedConnection(initiator: a, target: b, domain: 'general');
      await move(b, a, .active);
      await h.db.changeConnectionStatus(
        actorId: a,
        targetId: b,
        role: .peer,
        domain: .general,
        newStatus: .blocked,
      );

      await expectLater(move(b, a, .pending), throwsA(isA<Forbidden>()));
      final row = await h.exec("SELECT status FROM connections WHERE initiator_id = @a AND domain = 'fitness'", {
        'a': a,
      });
      expect(row.first[0], 'severed');
    });

    test('a request with nobody recorded as its author is still not its initiator\'s to answer', () async {
      final (a, b) = await pair();
      await h.seedConnection(initiator: a, target: b, status: 'pending');
      await h.exec('UPDATE connections SET status_by = NULL WHERE initiator_id = @a', {'a': a});

      await expectLater(move(a, b, .active), throwsA(isA<Forbidden>()));
      expect((await move(b, a, .active)).status, ConnectionStatus.active);
    });

    test('what a coaching connection shares is the live student\'s to choose', () async {
      final (coach, student) = await pair();
      await h.exec(
        'INSERT INTO connections (initiator_id, target_id, initiator_role, target_role, domain, status) '
        "VALUES (@c, @s, 'COACH', 'STUDENT', 'fitness', 'active')",
        {'c': coach, 's': student},
      );
      Future<Connection> share(ConnectionRole role) {
        return h.db.changeConnectionShares(
          actorId: student,
          targetId: coach,
          role: role,
          domain: .fitness,
          shares: {.goals},
        );
      }

      await expectLater(share(.coach), throwsA(isA<Forbidden>()), reason: 'that id is the coach\'s side');
      expect((await share(.student)).shares, ['goals']);

      await h.db.deleteConnection(actorId: student, targetId: coach, role: .student, domain: .fitness);
      await expectLater(share(.student), throwsA(isA<Forbidden>()), reason: 'an ended one shares nothing');
    });
  });
}

class _Harness extends DatabaseTestBase;
