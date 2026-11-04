import 'dart:convert';

import 'package:heart/models/coach_library.dart';
import 'package:heart_models/heart_models.dart';
import 'package:mockito/mockito.dart';
import 'package:test/test.dart';

import '../helpers/app_harness.dart';

void main() {
  late AppHarness app;

  setUp(() async => app = await AppHarness.start());
  tearDown(() => app.stop());

  const program = '01900000-0000-7000-8000-000000000001';
  const one = '01900000-0000-7000-8000-000000000002';
  const two = '01900000-0000-7000-8000-000000000003';

  CoachSendContext context({String? student}) {
    return (
      version: 1,
      body: <String, dynamic>{'name': 'Plan', 'sessions': const <Object?>[]},
      studentId: student,
      existingProgramId: null,
      studentBusy: false,
    );
  }

  test('a send through the real app reports each client, and one refusal stops none', () async {
    when(
      app.db.getCoachSendContext(coachId: anyNamed('coachId'), id: anyNamed('id'), connectionId: one),
    ).thenAnswer((_) async => context());
    when(
      app.db.getCoachSendContext(coachId: anyNamed('coachId'), id: anyNamed('id'), connectionId: two),
    ).thenAnswer((_) async => context(student: 's2'));
    when(
      app.db.matchExercisesForStudent(
        ids: anyNamed('ids'),
        coachId: anyNamed('coachId'),
        studentId: anyNamed('studentId'),
      ),
    ).thenAnswer((_) async => const {});
    when(
      app.db.createProgramOrExisting(
        userId: anyNamed('userId'),
        program: anyNamed('program'),
        sessions: anyNamed('sessions'),
        copy: anyNamed('copy'),
      ),
    ).thenAnswer((_) async => (Program(id: program, name: 'Plan'), true));

    final res = await app.send(
      'POST',
      '/library-programs/$program/send',
      body: {
        'connectionIds': [one, two],
      },
    );

    expect(res.status, 200);
    final deliveries = (jsonDecode(res.body) as Map)['deliveries'] as List;
    expect((deliveries.first as Map)['delivered'], isFalse);
    expect((deliveries.first as Map)['reason'], 'not_coaching');
    expect((deliveries.last as Map)['delivered'], isTrue);
  });
}
