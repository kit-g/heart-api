import 'package:heart_models/heart_models.dart';
import 'package:mockito/mockito.dart';
import 'package:test/test.dart';

import '../helpers/app_harness.dart';

/// Through the real app, so every middleware a route needs has to be there: these
/// answer 500 after their write when one isn't.
void main() {
  late AppHarness app;

  setUp(() async {
    app = await AppHarness.start();
    when(app.config.eventsQueueUrl).thenReturn('https://sqs.test/events');
    when(app.events.publish(queueUrl: anyNamed('queueUrl'), message: anyNamed('message'))).thenAnswer((_) async {});
    when(
      app.db.otherSideOf(actorId: anyNamed('actorId'), programId: anyNamed('programId')),
    ).thenAnswer((_) async => 'the-other-side');
    when(
      app.db.getCopyAccess(
        coachId: anyNamed('coachId'),
        studentId: anyNamed('studentId'),
        programId: anyNamed('programId'),
      ),
    ).thenAnswer((_) async => (readable: true, writable: true));
    when(
      app.db.matchExercisesForStudent(
        ids: anyNamed('ids'),
        coachId: anyNamed('coachId'),
        studentId: anyNamed('studentId'),
      ),
    ).thenAnswer((_) async => const {});
  });
  tearDown(() => app.stop());

  const program = '01900000-0000-7000-8000-000000000001';
  const session = '01900000-0000-7000-8000-000000000002';

  void told() {
    final message =
        verify(app.events.publish(queueUrl: anyNamed('queueUrl'), message: captureAnyNamed('message'))).captured.single
            as Map;
    expect(message['topic'], 'coaching.program_changed');
    expect(message['userId'], 'the-other-side');
  }

  void stubWriteSession(Template? answer) {
    when(
      app.db.writeSession(
        ownerId: anyNamed('ownerId'),
        actorId: anyNamed('actorId'),
        sessionId: anyNamed('sessionId'),
        body: anyNamed('body'),
        programId: anyNamed('programId'),
        baseRevision: anyNamed('baseRevision'),
        changeId: anyNamed('changeId'),
      ),
    ).thenAnswer((_) async => answer);
  }

  Template template() => Template.fromJson(const {'id': session, 'name': 'Day', 'order': 0, 'programId': program});

  const body = {'name': 'Day', 'exercises': <Object?>[]};

  test('a coach editing a session tells the student', () async {
    stubWriteSession(template());
    final res = await app.send('PUT', '/accounts/s/programs/$program/sessions/$session', body: body);
    expect(res.status, 200);
    told();
  });

  test('a coach deleting a session tells the student', () async {
    when(
      app.db.removeSession(
        ownerId: anyNamed('ownerId'),
        actorId: anyNamed('actorId'),
        sessionId: anyNamed('sessionId'),
        programId: anyNamed('programId'),
      ),
    ).thenAnswer((_) async => program);
    final res = await app.send('DELETE', '/accounts/s/programs/$program/sessions/$session');
    expect(res.status, 204);
    told();
  });

  test('a session already gone answers as deleted, so a retry isn\'t a failure, and tells nobody', () async {
    when(
      app.db.removeSession(
        ownerId: anyNamed('ownerId'),
        actorId: anyNamed('actorId'),
        sessionId: anyNamed('sessionId'),
        programId: anyNamed('programId'),
      ),
    ).thenAnswer((_) async => null);
    final res = await app.send('DELETE', '/accounts/s/programs/$program/sessions/$session');
    expect(res.status, 204);
    verifyNever(app.events.publish(queueUrl: anyNamed('queueUrl'), message: anyNamed('message')));
  });

  test('a push that can\'t go out doesn\'t turn a saved edit into an error', () async {
    stubWriteSession(template());
    when(
      app.events.publish(queueUrl: anyNamed('queueUrl'), message: anyNamed('message')),
    ).thenThrow(Exception('the queue is down'));
    final res = await app.send('PUT', '/accounts/s/programs/$program/sessions/$session', body: body);
    expect(res.status, 200);
  });

  test('a coach\'s custom exercise in a session edit goes through the student\'s own', () async {
    const coaches = '01900000-0000-7000-8000-00000000c0ac';
    const students = '01900000-0000-7000-8000-00000000057d';
    when(
      app.db.matchExercisesForStudent(
        ids: anyNamed('ids'),
        coachId: anyNamed('coachId'),
        studentId: anyNamed('studentId'),
      ),
    ).thenAnswer((_) async => const {coaches: students});
    stubWriteSession(template());
    final res = await app.send(
      'PUT',
      '/accounts/s/programs/$program/sessions/$session',
      body: {
        'name': 'Day',
        'exercises': [
          {
            'exercise': {'id': coaches},
            'sets': [
              {'reps': 5},
            ],
          },
        ],
      },
    );
    expect(res.status, 200);
    final written =
        verify(
              app.db.writeSession(
                ownerId: anyNamed('ownerId'),
                actorId: anyNamed('actorId'),
                sessionId: anyNamed('sessionId'),
                body: captureAnyNamed('body'),
                programId: anyNamed('programId'),
                baseRevision: anyNamed('baseRevision'),
                changeId: anyNamed('changeId'),
              ),
            ).captured.single
            as TemplateRequest;
    expect(written.exercises.single.exerciseId, students);
  });

  test('a coach\'s edit of a copy\'s fields keeps whether the student archived it', () async {
    when(
      app.db.getProgram(userId: anyNamed('userId'), programId: anyNamed('programId')),
    ).thenAnswer((_) async => Program(id: program, name: 'Plan', archived: true));
    when(
      app.db.writeProgramFields(
        ownerId: anyNamed('ownerId'),
        actorId: anyNamed('actorId'),
        programId: anyNamed('programId'),
        program: anyNamed('program'),
        baseRevision: anyNamed('baseRevision'),
        changeId: anyNamed('changeId'),
      ),
    ).thenAnswer((_) async => Program(id: program, name: 'Plan', archived: true));
    final res = await app.send('PUT', '/accounts/s/programs/$program', body: {'name': 'Plan'});
    expect(res.status, 200);
    final written =
        verify(
              app.db.writeProgramFields(
                ownerId: anyNamed('ownerId'),
                actorId: anyNamed('actorId'),
                programId: anyNamed('programId'),
                program: captureAnyNamed('program'),
                baseRevision: anyNamed('baseRevision'),
                changeId: anyNamed('changeId'),
              ),
            ).captured.single
            as Program;
    expect(written.archived, isTrue);
  });

  test('a coach\'s edit of a copy that isn\'t one is a 404, and tells nobody', () async {
    when(
      app.db.getProgram(userId: anyNamed('userId'), programId: anyNamed('programId')),
    ).thenAnswer((_) async => Program(id: program, name: 'Plan'));
    when(
      app.db.writeProgramFields(
        ownerId: anyNamed('ownerId'),
        actorId: anyNamed('actorId'),
        programId: anyNamed('programId'),
        program: anyNamed('program'),
        baseRevision: anyNamed('baseRevision'),
        changeId: anyNamed('changeId'),
      ),
    ).thenAnswer((_) async => null);
    final res = await app.send('PUT', '/accounts/s/programs/$program', body: {'name': 'Plan'});
    expect(res.status, 404);
    verifyNever(app.events.publish(queueUrl: anyNamed('queueUrl'), message: anyNamed('message')));
  });

  test('a student editing a session of a copy tells the coach', () async {
    stubWriteSession(template());
    final res = await app.send('PUT', '/templates/$session', body: body);
    expect(res.status, 200);
    told();
  });

  test('a student deleting a session of a copy tells the coach', () async {
    when(
      app.db.removeSession(
        ownerId: anyNamed('ownerId'),
        actorId: anyNamed('actorId'),
        sessionId: anyNamed('sessionId'),
        programId: anyNamed('programId'),
      ),
    ).thenAnswer((_) async => program);
    final res = await app.send('DELETE', '/templates/$session');
    expect(res.status, 204);
    told();
  });

  test('a student editing a copy\'s own fields tells the coach', () async {
    when(
      app.db.writeProgramFields(
        ownerId: anyNamed('ownerId'),
        actorId: anyNamed('actorId'),
        programId: anyNamed('programId'),
        program: anyNamed('program'),
        baseRevision: anyNamed('baseRevision'),
        changeId: anyNamed('changeId'),
      ),
    ).thenAnswer((_) async => Program(id: program, name: 'Plan'));
    final res = await app.send('PUT', '/programs/$program', body: {'name': 'Plan', 'archived': false});
    expect(res.status, 200);
    told();
  });

  test('a base past what a revision can be is a 400, not a 500', () async {
    final res = await app.send(
      'PUT',
      '/accounts/s/programs/$program/sessions/$session',
      body: {...body, 'baseRevision': 3000000000},
    );
    expect(res.status, 400);
  });
}
