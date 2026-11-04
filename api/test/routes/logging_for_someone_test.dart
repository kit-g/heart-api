import 'package:heart_models/heart_models.dart';
import 'package:mockito/mockito.dart';
import 'package:test/test.dart';

import '../helpers/app_harness.dart';

void main() {
  late AppHarness app;

  setUp(() async => app = await AppHarness.start());
  tearDown(() => app.stop());

  const workout = '01900000-0000-7000-8000-000000000001';

  test('logging through the real app has what it needs', () async {
    when(app.config.mediaDistribution).thenReturn('cdn.test');
    when(app.db.canLogFor(coachId: anyNamed('coachId'), studentId: anyNamed('studentId')))
        .thenAnswer((_) async => true);
    when(
      app.db.matchExercisesForStudent(
        ids: anyNamed('ids'),
        coachId: anyNamed('coachId'),
        studentId: anyNamed('studentId'),
      ),
    ).thenAnswer((_) async => const {});
    when(
      app.db.createWorkout(
        userId: anyNamed('userId'),
        body: anyNamed('body'),
        imageUrl: anyNamed('imageUrl'),
        loggedBy: 'u1',
      ),
    ).thenAnswer(
      (invocation) async => (
        Workout.fromRow({
          'id': workout,
          'name': 'In person',
          'started_at': DateTime.utc(2026),
          'exercises': const <Object?>[],
          'logged_by': 'u1',
        }, imageUrl: (key) => key),
        true,
      ),
    );

    final res = await app.send(
      'POST',
      '/accounts/s/workouts',
      body: {'id': workout, 'name': 'In person', 'start': '2026-10-01T10:00:00Z'},
    );
    expect(res.status, 201);
    final captured =
        verify(
              app.db.createWorkout(
                userId: captureAnyNamed('userId'),
                body: anyNamed('body'),
                imageUrl: anyNamed('imageUrl'),
                loggedBy: anyNamed('loggedBy'),
              ),
            ).captured.single
            as String;
    expect(captured, 's', reason: 'it is the student\'s');
  });

  test('someone who can\'t log for them is refused before anything is written', () async {
    when(app.db.canLogFor(coachId: anyNamed('coachId'), studentId: anyNamed('studentId')))
        .thenAnswer((_) async => false);
    final res = await app.send('POST', '/accounts/s/workouts', body: {'id': workout});
    expect(res.status, 403);
    verifyNever(
      app.db.createWorkout(
        userId: anyNamed('userId'),
        body: anyNamed('body'),
        imageUrl: anyNamed('imageUrl'),
        loggedBy: anyNamed('loggedBy'),
      ),
    );
  });

  for (final (what, body) in [
    ('no start', {'id': workout, 'name': 'In person'}),
    ('a start that is no time', {'id': workout, 'name': 'In person', 'start': 'yesterday'}),
    ('no name', {'id': workout, 'start': '2026-10-01T10:00:00Z'}),
    (
      'an exercise twice at one place',
      {
        'id': workout,
        'name': 'In person',
        'start': '2026-10-01T10:00:00Z',
        'exercises': [
          for (final id in [workout, '01900000-0000-7000-8000-000000000009'])
            {'exercise': id, 'order': 0, 'sets': const <Object?>[]},
        ],
      },
    ),
  ]) {
    test('a log with $what is refused before anything is written for it', () async {
      when(app.db.canLogFor(coachId: anyNamed('coachId'), studentId: anyNamed('studentId')))
          .thenAnswer((_) async => true);
      final res = await app.send('POST', '/accounts/s/workouts', body: body);
      expect(res.status, 400);
      verifyNever(
        app.db.matchExercisesForStudent(
          ids: anyNamed('ids'),
          coachId: anyNamed('coachId'),
          studentId: anyNamed('studentId'),
        ),
      );
      verifyNever(
        app.db.createWorkout(
          userId: anyNamed('userId'),
          body: anyNamed('body'),
          imageUrl: anyNamed('imageUrl'),
          loggedBy: anyNamed('loggedBy'),
        ),
      );
    });
  }

  group('a base the coach moves', () {
    const program = '01900000-0000-7000-8000-000000000003';
    const exercise = '01900000-0000-7000-8000-000000000004';
    final base = {'exerciseId': exercise, 'value': 100, 'workoutId': workout, 'at': '2026-10-01T11:00:00Z'};

    void access({required bool writable}) {
      when(
        app.db.getCopyAccess(
          coachId: anyNamed('coachId'),
          studentId: anyNamed('studentId'),
          programId: anyNamed('programId'),
        ),
      ).thenAnswer((_) async => (readable: true, writable: writable));
    }

    test('goes on the student\'s program, as one they logged, and tells the student', () async {
      access(writable: true);
      when(app.config.eventsQueueUrl).thenReturn('https://sqs.test/events');
      when(app.events.publish(queueUrl: anyNamed('queueUrl'), message: anyNamed('message'))).thenAnswer((_) async {});
      when(app.db.otherSideOf(actorId: anyNamed('actorId'), programId: anyNamed('programId')))
          .thenAnswer((_) async => 's');
      when(
        app.db.createProgramBase(
          userId: anyNamed('userId'),
          programId: anyNamed('programId'),
          base: anyNamed('base'),
          loggedBy: anyNamed('loggedBy'),
        ),
      ).thenAnswer(
        (_) async => (
          ProgramBase(id: workout, exerciseId: exercise, value: 100, workoutId: workout, at: DateTime.utc(2026)),
          true,
        ),
      );

      final res = await app.send('POST', '/accounts/s/programs/$program/bases', body: base);
      expect(res.status, 201);
      final captured = verify(
        app.db.createProgramBase(
          userId: captureAnyNamed('userId'),
          programId: anyNamed('programId'),
          base: anyNamed('base'),
          loggedBy: captureAnyNamed('loggedBy'),
        ),
      ).captured;
      expect(captured, ['s', 'u1']);
      final message =
          verify(app.events.publish(queueUrl: anyNamed('queueUrl'), message: captureAnyNamed('message')))
                  .captured
                  .single
              as Map;
      expect((message['topic'], message['userId']), ('coaching.program_changed', 's'));
    });

    test('not on a program they can no longer change', () async {
      access(writable: false);
      final res = await app.send('POST', '/accounts/s/programs/$program/bases', body: base);
      expect(res.status, 403);
      verifyNever(
        app.db.createProgramBase(
          userId: anyNamed('userId'),
          programId: anyNamed('programId'),
          base: anyNamed('base'),
          loggedBy: anyNamed('loggedBy'),
        ),
      );
    });
  });

  test('a plan only for a client they can log for', () async {
    when(app.db.canLogFor(coachId: anyNamed('coachId'), studentId: anyNamed('studentId')))
        .thenAnswer((_) async => false);
    final res = await app.send(
      'PUT',
      '/accounts/s/workouts/$workout/plan',
      body: {
        'plan': {'exercises': <Object?>[]},
      },
    );
    expect(res.status, 403);
    verifyNever(
      app.db.savePlan(
        userId: anyNamed('userId'),
        workoutId: anyNamed('workoutId'),
        plan: anyNamed('plan'),
        loggedBy: anyNamed('loggedBy'),
      ),
    );
  });
}
