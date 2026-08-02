import 'package:heart_models/heart_models.dart';
import 'package:test/test.dart';

void main() {
  group('ConnectionRole', () {
    test('fromString parses correctly', () {
      expect(ConnectionRole.fromString('COACH'), equals(ConnectionRole.coach));
      expect(ConnectionRole.fromString('student'), equals(ConnectionRole.student));
      expect(ConnectionRole.fromString('PeEr'), equals(ConnectionRole.peer));
    });

    // It used to fall back to peer, so asking to be someone's coach and typo'ing
    // it produced a peer connection and a 200.
    test('fromString throws on an unknown role rather than defaulting', () {
      expect(() => ConnectionRole.fromString('unknown'), throwsArgumentError);
      expect(() => ConnectionRole.fromString(''), throwsArgumentError);
    });

    test('reciprocal returns the opposite role', () {
      expect(ConnectionRole.coach.reciprocal, equals(ConnectionRole.student));
      expect(ConnectionRole.student.reciprocal, equals(ConnectionRole.coach));
      expect(ConnectionRole.peer.reciprocal, equals(ConnectionRole.peer));
    });
  });

  group('ConnectionDomain', () {
    test('fromString parses correctly', () {
      expect(ConnectionDomain.fromString('fitness'), equals(ConnectionDomain.fitness));
      expect(ConnectionDomain.fromString('SWIMMING'), equals(ConnectionDomain.swimming));
      expect(ConnectionDomain.fromString('RuNnInG'), equals(ConnectionDomain.running));
      expect(ConnectionDomain.fromString('general'), equals(ConnectionDomain.general));
    });

    test('fromString throws on an unknown domain rather than defaulting', () {
      expect(() => ConnectionDomain.fromString('unknown'), throwsArgumentError);
    });
  });

  group('ConnectionStatus', () {
    test('fromString parses correctly', () {
      expect(ConnectionStatus.fromString('pending'), equals(ConnectionStatus.pending));
      expect(ConnectionStatus.fromString('ACTIVE'), equals(ConnectionStatus.active));
      expect(ConnectionStatus.fromString('blocked'), equals(ConnectionStatus.blocked));
    });

    test('fromString throws on an unknown status rather than defaulting', () {
      expect(() => ConnectionStatus.fromString('unknown'), throwsArgumentError);
    });

    test('accepting and declining are the target\'s alone', () {
      expect(ConnectionStatus.active.isTheTargetsAlone, isTrue);
      expect(ConnectionStatus.declined.isTheTargetsAlone, isTrue);
      for (final other in [
        ConnectionStatus.pending,
        ConnectionStatus.paused,
        ConnectionStatus.severed,
        ConnectionStatus.blocked,
      ]) {
        expect(other.isTheTargetsAlone, isFalse, reason: '${other.name} is either party\'s to make');
      }
    });

    test('canTransitionTo enforces valid state changes', () {
      // Same state transition is blocked
      expect(ConnectionStatus.active.canTransitionTo(ConnectionStatus.active), isFalse);

      // Pending transitions
      expect(ConnectionStatus.pending.canTransitionTo(ConnectionStatus.active), isTrue);
      expect(ConnectionStatus.pending.canTransitionTo(ConnectionStatus.declined), isTrue);
      expect(ConnectionStatus.pending.canTransitionTo(ConnectionStatus.severed), isFalse);

      // Active transitions
      expect(ConnectionStatus.active.canTransitionTo(ConnectionStatus.paused), isTrue);
      expect(ConnectionStatus.active.canTransitionTo(ConnectionStatus.severed), isTrue);
      expect(ConnectionStatus.active.canTransitionTo(ConnectionStatus.pending), isFalse);

      // Paused transitions
      expect(ConnectionStatus.paused.canTransitionTo(ConnectionStatus.active), isTrue);
      expect(ConnectionStatus.paused.canTransitionTo(ConnectionStatus.severed), isTrue);

      // Blocked transitions
      expect(ConnectionStatus.blocked.canTransitionTo(ConnectionStatus.severed), isTrue);
      expect(ConnectionStatus.blocked.canTransitionTo(ConnectionStatus.active), isFalse);
    });
  });

  group('Connection', () {
    final now = DateTime.utc(2025, 1, 1, 12, 0, 0);

    test('fromRow parses database row correctly', () {
      final row = {
        'target_id': 'user_123',
        'role': 'COACH',
        'domain': 'fitness',
        'status': 'active',
        'created_at': now.toIso8601String(),
      };

      final connection = Connection.fromRow(row);

      expect(connection.targetId, equals('user_123'));
      expect(connection.role, equals(ConnectionRole.coach));
      expect(connection.domain, equals(ConnectionDomain.fitness));
      expect(connection.status, equals(ConnectionStatus.active));
      expect(connection.createdAt, equals(now));
      expect(connection.id, equals('user_123|COACH|FITNESS'));
    });

    test('fromId parses id string correctly', () {
      final id = 'user_123|COACH|FITNESS';
      final (targetId, role, domain) = Connection.fromId(id);

      expect(targetId, equals('user_123'));
      expect(role, equals(ConnectionRole.coach));
      expect(domain, equals(ConnectionDomain.fitness));
    });

    test('fromId throws on invalid format', () {
      expect(() => Connection.fromId('invalid_id'), throwsArgumentError);
      expect(() => Connection.fromId('user_123|COACH'), throwsArgumentError);
    });

    test('toMap converts model to JSON format', () {
      final connection = Connection(
        targetId: 'user_123',
        role: ConnectionRole.student,
        domain: ConnectionDomain.swimming,
        status: ConnectionStatus.pending,
        createdAt: now,
      );

      final map = connection.toMap();

      expect(
        map,
        equals({
          'id': 'user_123|STUDENT|SWIMMING',
          'targetId': 'user_123',
          'role': 'STUDENT',
          'domain': 'SWIMMING',
          'status': 'pending',
          'createdAt': now.toIso8601String(),
        }),
      );
    });
  });

  group('ConnectionListResponse', () {
    test('toMap serializes list of connections', () {
      final now = DateTime.utc(2025, 1, 1, 12, 0, 0);
      final c1 = Connection(
        targetId: 'user_1',
        role: ConnectionRole.peer,
        domain: ConnectionDomain.general,
        status: ConnectionStatus.active,
        createdAt: now,
      );

      final response = ConnectionListResponse([c1]);

      expect(
        response.toMap(),
        equals({
          'connections': [
            {
              'id': 'user_1|PEER|GENERAL',
              'targetId': 'user_1',
              'role': 'PEER',
              'domain': 'GENERAL',
              'status': 'active',
              'createdAt': now.toIso8601String(),
            },
          ],
        }),
      );
    });
  });
}
