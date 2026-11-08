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

  test('a student is told of a copy the send made, and not of one they already held', () async {
    const held = '01900000-0000-7000-8000-0000000000aa';
    when(
      app.db.getCoachSendContext(coachId: anyNamed('coachId'), id: anyNamed('id'), connectionId: one),
    ).thenAnswer((_) async => context(student: 's1'));
    when(
      app.db.getCoachSendContext(coachId: anyNamed('coachId'), id: anyNamed('id'), connectionId: two),
    ).thenAnswer((_) async => context(student: 's2', existing: held));
    stubMatch();
    when(
      app.db.createProgramOrExisting(
        userId: anyNamed('userId'),
        program: anyNamed('program'),
        sessions: anyNamed('sessions'),
        copy: anyNamed('copy'),
      ),
    ).thenAnswer((_) async => (Program(id: program, name: 'Plan'), true));
    when(app.config.eventsQueueUrl).thenReturn('https://sqs.test/events');
    when(app.events.publish(queueUrl: anyNamed('queueUrl'), message: anyNamed('message'))).thenAnswer((_) async {});

    final res = await app.send(
      'POST',
      '/library-programs/$program/send',
      body: {
        'connectionIds': [one, two],
      },
    );

    expect(res.status, 200);
    final message =
        verify(app.events.publish(queueUrl: anyNamed('queueUrl'), message: captureAnyNamed('message'))).captured.single
            as Map;
    expect(message['userId'], 's1');
    expect(message['topic'], 'coaching.program_received');
    expect(message['connectionId'], one);
    expect(message['data'], {'programId': program});
  });

  test('a push that fails leaves the copy delivered', () async {
    when(
      app.db.getCoachSendContext(coachId: anyNamed('coachId'), id: anyNamed('id'), connectionId: one),
    ).thenAnswer((_) async => context(student: 's1'));
    stubMatch();
    when(
      app.db.createProgramOrExisting(
        userId: anyNamed('userId'),
        program: anyNamed('program'),
        sessions: anyNamed('sessions'),
        copy: anyNamed('copy'),
      ),
    ).thenAnswer((_) async => (Program(id: program, name: 'Plan'), true));
    when(app.config.eventsQueueUrl).thenReturn('https://sqs.test/events');
    when(
      app.events.publish(queueUrl: anyNamed('queueUrl'), message: anyNamed('message')),
    ).thenThrow(Exception('queue down'));

    final res = await app.send(
      'POST',
      '/library-programs/$program/send',
      body: {
        'connectionIds': [one],
      },
    );

    expect(res.status, 200);
    expect((((jsonDecode(res.body) as Map)['deliveries'] as List).single as Map)['delivered'], isTrue);
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

  test("another coach's program has no holders to list: 404, as reading it is", () async {
    when(
      app.db.getCoachProgram(coachId: anyNamed('coachId'), id: anyNamed('id')),
    ).thenThrow(const NotFound(type: 'Library program', id: program));

    final res = await app.send('GET', '/library-programs/$program/holders');

    expect(res.status, 404);
    verifyNever(app.db.getCoachProgramHolders(coachId: anyNamed('coachId'), id: anyNamed('id')));
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

  CoachProgram saved({String id = program}) {
    return CoachProgram(id: id, name: 'Plan', version: 2, updatedAt: DateTime.utc(2026, 11));
  }

  test('saving a version keeps the coach\'s program under the id in the path', () async {
    when(
      app.db.saveCoachProgram(
        coachId: anyNamed('coachId'),
        id: anyNamed('id'),
        name: anyNamed('name'),
        body: anyNamed('body'),
      ),
    ).thenAnswer((_) async => saved());

    final res = await app.send(
      'PUT',
      '/library-programs/$program',
      body: {
        'name': 'Plan',
        'sessions': [
          {'name': 'A'},
        ],
      },
    );

    expect(res.status, 200);
    final body =
        verify(
              app.db.saveCoachProgram(coachId: 'u1', id: program, name: 'Plan', body: captureAnyNamed('body')),
            ).captured.single
            as Map;
    expect(body, isNot(contains('id')));
    expect(body['sessions'] as List, hasLength(1));
  });

  test('a version under an id that was never one is refused before it is saved', () async {
    final res = await app.send('PUT', '/library-programs/abc', body: {'name': 'Plan'});

    expect(res.status, 400);
    verifyZeroInteractions(app.db);
  });

  test('lists the coach\'s library, with the next cursor while there are more', () async {
    when(
      app.db.getCoachPrograms(coachId: anyNamed('coachId'), cursor: anyNamed('cursor'), limit: anyNamed('limit')),
    ).thenAnswer((_) async => Page(items: [saved(id: two)], hasMore: true));

    final res = await app.send('GET', '/library-programs?cursor=$one&limit=1');

    expect(res.status, 200);
    final json = jsonDecode(res.body) as Map;
    expect((json['programs'] as List).single, containsPair('id', two));
    expect(json['cursor'], two);
    verify(app.db.getCoachPrograms(coachId: 'u1', cursor: one, limit: 1)).called(1);
  });

  test('the holders of the coach\'s own program are listed', () async {
    when(app.db.getCoachProgram(coachId: anyNamed('coachId'), id: anyNamed('id'))).thenAnswer((_) async => saved());
    when(app.db.getCoachProgramHolders(coachId: anyNamed('coachId'), id: anyNamed('id'))).thenAnswer(
      (_) async => [CoachProgramHolder(connectionId: one, studentId: 's1', programId: two, version: 1)],
    );

    final res = await app.send('GET', '/library-programs/$program/holders');

    expect(res.status, 200);
    expect(CoachProgramHolders.fromJson(jsonDecode(res.body) as Map).holders.single.studentId, 's1');
    verify(app.db.getCoachProgramHolders(coachId: 'u1', id: program)).called(1);
  });

  test('a student starts a program that was waiting for them, 204', () async {
    when(app.db.startProgram(userId: anyNamed('userId'), programId: anyNamed('programId'))).thenAnswer((_) async {});

    final res = await app.send('POST', '/programs/$program/start');

    expect(res.status, 204);
    verify(app.db.startProgram(userId: 'u1', programId: program)).called(1);
  });
}
