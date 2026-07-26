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
        initiatorId: student,
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
        initiatorId: a,
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
        initiatorId: a,
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
        initiatorId: coach,
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
        initiatorId: a,
        targetId: b,
        role: ConnectionRole.peer,
        domain: ConnectionDomain.fitness,
      );

      expect(
        await h.db.getConnection(
          initiatorId: a,
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
        initiatorId: b,
        targetId: a,
        role: ConnectionRole.peer,
        domain: ConnectionDomain.fitness,
      );
      expect(await h.db.getConnections(a), isEmpty);
    });

    test('is a no-op when there is no connection', () async {
      final (a, b) = await pair();
      await h.db.deleteConnection(
        initiatorId: a,
        targetId: b,
        role: ConnectionRole.peer,
        domain: ConnectionDomain.fitness,
      );
      expect(await h.db.getConnections(a), isEmpty);
    });
  });

  group('changeConnectionStatus', () {
    test('transitions a pending connection to active and persists it', () async {
      final (a, b) = await pair();
      await h.db.createConnection(
        initiatorId: a,
        targetId: b,
        role: ConnectionRole.peer,
        domain: ConnectionDomain.fitness,
      );

      final updated = await h.db.changeConnectionStatus(
        initiatorId: a,
        targetId: b,
        role: ConnectionRole.peer,
        domain: ConnectionDomain.fitness,
        newStatus: ConnectionStatus.active,
      );
      expect(updated.status, ConnectionStatus.active);

      // Persisted, and now visible as an active connection.
      final reread = await h.db.getConnection(
        initiatorId: a,
        targetId: b,
        role: ConnectionRole.peer,
        domain: ConnectionDomain.fitness,
      );
      expect(reread?.status, ConnectionStatus.active);
      expect(await h.db.areConnected(userA: a, userB: b), isTrue);
    });

    test('throws StateError when there is no connection to update', () async {
      final (a, b) = await pair();
      await expectLater(
        h.db.changeConnectionStatus(
          initiatorId: a,
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
          initiatorId: a,
          targetId: b,
          role: ConnectionRole.peer,
          domain: ConnectionDomain.fitness,
          newStatus: ConnectionStatus.severed,
        ),
        throwsA(isA<StateError>()),
      );

      // Left untouched.
      final unchanged = await h.db.getConnection(
        initiatorId: a,
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

class _Harness extends DatabaseTestBase {}
