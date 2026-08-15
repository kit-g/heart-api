@Tags(['db'])
library;

import 'package:heart/models/errors.dart';
import 'package:heart_models/heart_models.dart';
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
    test('removes the connection so neither side can read it', () async {
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

      expect(
        await h.db.getConnection(
          actorId: a,
          targetId: b,
          role: ConnectionRole.peer,
          domain: ConnectionDomain.fitness,
        ),
        isNull,
      );
      expect(await h.db.getConnections(a), isEmpty);
      expect(await h.db.getConnections(b), isEmpty);
    });

    test('deletes regardless of which side is named as initiator', () async {
      final (a, b) = await pair();
      await h.db.createConnection(
        initiatorId: a,
        targetId: b,
        role: ConnectionRole.peer,
        domain: ConnectionDomain.fitness,
      );

      // Delete addressed from the target's perspective still clears the pair.
      await h.db.deleteConnection(
        actorId: b,
        targetId: a,
        role: ConnectionRole.peer,
        domain: ConnectionDomain.fitness,
      );
      expect(await h.db.getConnections(a), isEmpty);
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

    test('the blocker can still delete their own block', () async {
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
      expect(await h.db.getConnections(blocker), isEmpty);
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

      final outcomes = await Future.wait([
        for (var i = 0; i < 8; i++)
          h.db
              .changeConnectionStatus(
                actorId: b,
                targetId: a,
                role: ConnectionRole.peer,
                domain: ConnectionDomain.fitness,
                newStatus: ConnectionStatus.active,
              )
              .then((_) => true)
              .onError((_, _) => false),
      ]);

      expect(outcomes.where((won) => won), hasLength(1));

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
}

class _Harness extends DatabaseTestBase;
