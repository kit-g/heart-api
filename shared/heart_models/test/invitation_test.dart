import 'package:heart_models/heart_models.dart';
import 'package:test/test.dart';

import 'wire.dart';

void main() {
  const connection = '01900000-0000-7000-8000-000000000001';
  const program = '01900000-0000-7000-8000-000000000002';
  final at = DateTime.utc(2026, 11, 1, 9, 30);
  final later = DateTime.utc(2026, 11, 2, 18);

  group('invitations', () {
    final accepted = Connection.fromRow({
      'target_id': 'coach',
      'role': 'COACH',
      'domain': 'fitness',
      'status': 'active',
      'created_at': at,
      'connection_id': connection,
      'accepted_at': later,
      'shares': ['history'],
    });

    test('AcceptedInvitation round-trips, with a program and without', () {
      expectRoundTrip(AcceptedInvitation(accepted), AcceptedInvitation.fromJson);
      expectRoundTrip(
        AcceptedInvitation(
          accepted,
          delivery: const ProgramDelivery(connectionId: connection, delivered: true, programId: program),
        ),
        AcceptedInvitation.fromJson,
      );
    });

    // `POST /invitations/:token/accept`: the connection, and how the program went
    test('AcceptedInvitation reads what accepting answers', () {
      final none = AcceptedInvitation.fromJson(wire(AcceptedInvitation(accepted)));
      expect(none.connection.connectionId, connection);
      expect(none.delivery, isNull);

      final arrived = AcceptedInvitation.fromJson(
        wire(
          AcceptedInvitation(
            accepted,
            delivery: const ProgramDelivery(connectionId: connection, delivered: true, programId: program),
          ),
        ),
      );
      expect(arrived.delivery?.delivered, isTrue);
      expect(arrived.delivery?.programId, program);
      expect(arrived.delivery?.connectionId, connection);

      final refused = AcceptedInvitation.fromJson(
        wire(
          AcceptedInvitation(
            accepted,
            delivery: const ProgramDelivery(connectionId: connection, delivered: false, reason: 'program_limit'),
          ),
        ),
      );
      expect(refused.delivery?.delivered, isFalse);
      expect(refused.delivery?.programId, isNull);
    });

    final blocked = BlockedPerson.fromRow({
      'blocked_id': 'u9',
      'username': 'Pat',
      'avatar_url': null,
      'created_at': at,
    });

    test('BlockedPerson round-trips', () => expectRoundTrip(blocked, BlockedPerson.fromJson));

    test('BlockedPerson reads a page of blocks as the API sends it', () {
      final read = readEach([wire(blocked)], BlockedPerson.fromJson);
      expect(read.items.single.id, 'u9');
      expect(read.items.single.name, 'Pat');
      expect(read.items.single.avatar, isNull);
      expect(read.items.single.since, at);
    });
  });
}
