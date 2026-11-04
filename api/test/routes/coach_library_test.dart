import 'dart:convert';

import 'package:heart/models/coach_library.dart';
import 'package:heart/models/errors.dart';
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

  CoachSendContext context({String? student, Map<String, dynamic>? body, String? existing}) {
    return (
      version: 1,
      body: body ?? <String, dynamic>{'name': 'Plan', 'sessions': const <Object?>[]},
      studentId: student,
      existingProgramId: existing,
      existingVersion: null,
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

  void stubMatch() {
    when(
      app.db.matchExercisesForStudent(
        ids: anyNamed('ids'),
        coachId: anyNamed('coachId'),
        studentId: anyNamed('studentId'),
      ),
    ).thenAnswer((_) async => const {});
  }

  test('a stored version that no longer parses is one client not delivered, not a failed send', () async {
    when(
      app.db.getCoachSendContext(coachId: anyNamed('coachId'), id: anyNamed('id'), connectionId: one),
    ).thenAnswer((_) async => context(student: 's1', body: {'name': ''}));
    when(
      app.db.getCoachSendContext(coachId: anyNamed('coachId'), id: anyNamed('id'), connectionId: two),
    ).thenAnswer((_) async => context(student: 's2'));
    stubMatch();
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
    expect((deliveries.last as Map)['delivered'], isTrue);
  });

  test('a copy another send made first answers that copy', () async {
    const theirs = '01900000-0000-7000-8000-0000000000aa';
    var reads = 0;
    when(
      app.db.getCoachSendContext(coachId: anyNamed('coachId'), id: anyNamed('id'), connectionId: one),
    ).thenAnswer((_) async => reads++ == 0 ? context(student: 's1') : context(student: 's1', existing: theirs));
    stubMatch();
    when(
      app.db.createProgramOrExisting(
        userId: anyNamed('userId'),
        program: anyNamed('program'),
        sessions: anyNamed('sessions'),
        copy: anyNamed('copy'),
      ),
    ).thenThrow(const Conflict(code: 'already_sent', reason: 'they hold one'));

    final res = await app.send(
      'POST',
      '/library-programs/$program/send',
      body: {
        'connectionIds': [one],
      },
    );

    expect(res.status, 200);
    final delivery = ((jsonDecode(res.body) as Map)['deliveries'] as List).single as Map;
    expect(delivery['delivered'], isTrue);
    expect(delivery['programId'], theirs);
  });

  for (final (method, path) in [
    ('GET', '/library-programs/abc'),
    ('GET', '/library-programs/abc/holders'),
    ('DELETE', '/library-programs/abc'),
    ('POST', '/library-programs/abc/send'),
    ('POST', '/library-programs/abc/update'),
    ('POST', '/programs/abc/start'),
  ]) {
    test('an id that was never one is a 404, not a cast that fails: $method $path', () async {
      final res = await app.send(
        method,
        path,
        body: method == 'POST'
            ? {
                'connectionIds': [one],
              }
            : null,
      );
      expect(res.status, 404);
    });
  }

  test('a cursor that was never one is a 400, not a cast that fails', () async {
    final res = await app.send('GET', '/library-programs?cursor=abc');
    expect(res.status, 400);
  });
}
