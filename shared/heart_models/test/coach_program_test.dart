import 'package:heart_models/heart_models.dart';
import 'package:test/test.dart';

import 'wire.dart';

void main() {
  const connection = '01900000-0000-7000-8000-000000000001';
  const program = '01900000-0000-7000-8000-000000000002';
  const session = '01900000-0000-7000-8000-000000000003';
  final at = DateTime.utc(2026, 11, 1, 9, 30);

  group('coach library', () {
    final row = {
      'id': program,
      'name': 'Plan',
      'version': 2,
      'body': {
        'name': 'Plan',
        'sessions': [
          {'name': 'Day', 'exercises': <Object?>[]},
        ],
      },
      'updated_at': at,
    };

    test('CoachProgram round-trips, with a body and without', () {
      expectRoundTrip(CoachProgram.fromRow(row), CoachProgram.fromJson);
      expectRoundTrip(CoachProgram.fromRow({...row, 'body': null}), CoachProgram.fromJson);
    });

    test('CoachProgram reads one program as the API sends it', () {
      final read = CoachProgram.fromJson(wire(CoachProgram.fromRow(row)));
      expect(read.version, 2);
      expect(read.body?['sessions'], hasLength(1));
      expect(read.updatedAt, at);
    });

    final holder = CoachProgramHolder.fromRow({
      'connection_id': connection,
      'student_id': 's1',
      'username': 'Sam',
      'avatar_url': null,
      'program_id': program,
      'library_version': 1,
    });

    test('CoachProgramHolder round-trips', () => expectRoundTrip(holder, CoachProgramHolder.fromJson));

    test('CoachProgramHolders round-trips and reads as the API sends it', () {
      expectRoundTrip(CoachProgramHolders([holder]), CoachProgramHolders.fromJson);
      final read = CoachProgramHolders.fromJson(wire(CoachProgramHolders([holder])));
      expect(read.holders.single.studentName, 'Sam');
      expect(read.holders.single.studentAvatar, isNull);
      expect(read.holders.single.version, 1);
    });

    test('ProgramDelivery round-trips', () {
      expectRoundTrip(
        const ProgramDelivery(connectionId: connection, delivered: true, programId: program),
        ProgramDelivery.fromJson,
      );
      expectRoundTrip(
        const ProgramDelivery(connectionId: connection, delivered: false, reason: 'program_limit'),
        ProgramDelivery.fromJson,
      );
    });

    // the deliveries `POST /library-programs/:id/send` answers in
    // api/test/routes/coach_library_test.dart: one refused, one arrived
    test('ProgramDeliveries reads a send as the API answers it', () {
      final deliveries = const ProgramDeliveries([
        ProgramDelivery(connectionId: connection, delivered: false, reason: 'not_coaching'),
        ProgramDelivery(connectionId: session, delivered: true, programId: program),
      ]);
      expectRoundTrip(deliveries, ProgramDeliveries.fromJson);
      final read = ProgramDeliveries.fromJson(wire(deliveries));
      expect(read.deliveries.first.delivered, isFalse);
      expect(read.deliveries.first.reason, 'not_coaching');
      expect(read.deliveries.last.programId, program);
    });
  });
}
