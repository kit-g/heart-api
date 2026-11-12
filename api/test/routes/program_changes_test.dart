import 'dart:convert';

import 'package:heart/models/errors.dart';
import 'package:heart/models/coach_library.dart';
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

  void access({required bool readable, required bool writable}) {
    when(
      app.db.getCopyAccess(
        coachId: anyNamed('coachId'),
        studentId: anyNamed('studentId'),
        programId: anyNamed('programId'),
      ),
    ).thenAnswer((_) async => (readable: readable, writable: writable));
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

  group('a copy\'s history', () {
    const change = '01900000-0000-7000-8000-000000000003';

    ProgramChange recorded({String? sessionId, Map<String, dynamic>? before, int revision = 4}) {
      return ProgramChange(
        id: change,
        programId: program,
        sessionId: sessionId,
        kind: 'edit',
        revision: revision,
        before: before,
        at: DateTime.utc(2026, 11),
      );
    }

    void stubChange(ProgramChange? answer) {
      when(
        app.db.getProgramChange(
          ownerId: anyNamed('ownerId'),
          programId: anyNamed('programId'),
          changeId: anyNamed('changeId'),
        ),
      ).thenAnswer(
        (_) async => switch (answer) {
          final ProgramChange change => (change: change, links: null),
          null => null,
        },
      );
    }

    void stubWriteFields() {
      when(
        app.db.writeProgramFields(
          ownerId: anyNamed('ownerId'),
          actorId: anyNamed('actorId'),
          programId: anyNamed('programId'),
          program: anyNamed('program'),
          baseRevision: anyNamed('baseRevision'),
          changeId: anyNamed('changeId'),
          kind: anyNamed('kind'),
        ),
      ).thenAnswer((_) async => Program(id: program, name: 'Before'));
    }

    test('the owner reads what changed after a cursor', () async {
      when(
        app.db.getProgramChanges(
          ownerId: anyNamed('ownerId'),
          programId: anyNamed('programId'),
          since: anyNamed('since'),
        ),
      ).thenAnswer((_) async => Page(items: [recorded()], hasMore: false));

      final res = await app.send('GET', '/programs/$program/changes?since=c1');

      expect(res.status, 200);
      expect(((jsonDecode(res.body) as Map)['changes'] as List).single, containsPair('id', change));
      verify(app.db.getProgramChanges(ownerId: 'u1', programId: program, since: 'c1')).called(1);
    });

    test('putting back a change that isn\'t this copy\'s is a 404, and tells nobody', () async {
      stubChange(null);

      final res = await app.send('POST', '/programs/$program/changes/$change/revert');

      expect(res.status, 404);
      verifyNever(app.events.publish(queueUrl: anyNamed('queueUrl'), message: anyNamed('message')));
    });

    test(
      'putting back a change to the program\'s fields writes what was there as a revert, and tells the coach',
      () async {
        stubChange(recorded(before: {'name': 'Before'}));
        stubWriteFields();

        final res = await app.send('POST', '/programs/$program/changes/$change/revert');

        expect(res.status, 204);
        final written =
            verify(
                  app.db.writeProgramFields(
                    ownerId: 'u1',
                    actorId: 'u1',
                    programId: program,
                    program: captureAnyNamed('program'),
                    baseRevision: 4,
                    changeId: anyNamed('changeId'),
                    kind: 'revert',
                  ),
                ).captured.single
                as Program;
        expect(written.name, 'Before');
        told();
      },
    );

    test('putting back the creation of a session already gone is a 404, and tells nobody', () async {
      stubChange(recorded(sessionId: session));
      when(
        app.db.removeSession(
          ownerId: anyNamed('ownerId'),
          actorId: anyNamed('actorId'),
          sessionId: anyNamed('sessionId'),
          programId: anyNamed('programId'),
          baseRevision: anyNamed('baseRevision'),
          kind: anyNamed('kind'),
        ),
      ).thenAnswer((_) async => null);

      final res = await app.send('POST', '/programs/$program/changes/$change/revert');

      expect(res.status, 404);
      verifyNever(app.events.publish(queueUrl: anyNamed('queueUrl'), message: anyNamed('message')));
    });

    test('a coach puts back a change on the student\'s copy, as the student\'s', () async {
      stubChange(recorded(before: {'name': 'Before'}));
      stubWriteFields();

      final res = await app.send('POST', '/accounts/s/programs/$program/changes/$change/revert');

      expect(res.status, 204);
      verify(app.db.getProgramChange(ownerId: 's', programId: program, changeId: change)).called(1);
      verify(
        app.db.writeProgramFields(
          ownerId: 's',
          actorId: 'u1',
          programId: program,
          program: anyNamed('program'),
          baseRevision: 4,
          changeId: anyNamed('changeId'),
          kind: 'revert',
        ),
      ).called(1);
      told();
    });

    test('a coach who can no longer change the copy can\'t put anything back', () async {
      access(readable: true, writable: false);

      final res = await app.send('POST', '/accounts/s/programs/$program/changes/$change/revert');

      expect(res.status, 403);
      verifyNever(
        app.db.getProgramChange(
          ownerId: anyNamed('ownerId'),
          programId: anyNamed('programId'),
          changeId: anyNamed('changeId'),
        ),
      );
    });

    test('a coach reads the history of the student\'s copy, as one they sent', () async {
      when(
        app.db.getProgramChanges(
          ownerId: anyNamed('ownerId'),
          programId: anyNamed('programId'),
          since: anyNamed('since'),
          readerId: anyNamed('readerId'),
        ),
      ).thenAnswer((_) async => Page(items: [recorded()], hasMore: false));

      final res = await app.send('GET', '/accounts/s/programs/$program/changes');

      expect(res.status, 200);
      verify(app.db.getProgramChanges(ownerId: 's', programId: program, since: null, readerId: 'u1')).called(1);
    });

    test('a coach without a view of the student reads no history', () async {
      when(
        app.db.getProgramChanges(
          ownerId: anyNamed('ownerId'),
          programId: anyNamed('programId'),
          since: anyNamed('since'),
          readerId: anyNamed('readerId'),
        ),
      ).thenThrow(const Forbidden(reason: 'no'));

      final res = await app.send('GET', '/accounts/s/programs/$program/changes');

      expect(res.status, 403);
    });
  });

  group('a coach reading copies', () {
    test('lists the copies they sent this student', () async {
      when(
        app.db.getCopies(coachId: anyNamed('coachId'), studentId: anyNamed('studentId')),
      ).thenAnswer((_) async => [Program(id: program, name: 'Plan')]);

      final res = await app.send('GET', '/accounts/s/programs');

      expect(res.status, 200);
      expect(((jsonDecode(res.body) as Map)['programs'] as List).single, containsPair('id', program));
      verify(app.db.getCopies(coachId: 'u1', studentId: 's')).called(1);
    });

    test('reads one with its sessions and a position worked out from what they can see', () async {
      when(
        app.db.readCopy(
          coachId: anyNamed('coachId'),
          studentId: anyNamed('studentId'),
          programId: anyNamed('programId'),
        ),
      ).thenAnswer(
        (_) async => (
          program: Program(id: program, name: 'Plan', sessions: const [session]),
          sessions: [template()],
          actions: const <ProgramAction>[],
          marks: const <ProgramMark>[],
        ),
      );

      final res = await app.send('GET', '/accounts/s/programs/$program');

      expect(res.status, 200);
      final view = CoachProgramView.fromJson(jsonDecode(res.body) as Map);
      expect(view.program.id, program);
      expect(view.sessions.single.id, session);
      expect(view.position, isNotEmpty);
      verify(app.db.readCopy(coachId: 'u1', studentId: 's', programId: program)).called(1);
      verifyNever(app.db.getProgramMarks(userId: anyNamed('userId'), programId: anyNamed('programId')));
    });

    test('a coach without a view of the student reads nothing of the copy', () async {
      when(
        app.db.readCopy(
          coachId: anyNamed('coachId'),
          studentId: anyNamed('studentId'),
          programId: anyNamed('programId'),
        ),
      ).thenThrow(const Forbidden(reason: 'no'));

      final res = await app.send('GET', '/accounts/s/programs/$program');

      expect(res.status, 403);
    });
  });

  test('a coach\'s edit of a session the copy no longer has puts it back under its own id', () async {
    stubWriteSession(null);
    when(
      app.db.restoreSession(
        ownerId: anyNamed('ownerId'),
        actorId: anyNamed('actorId'),
        programId: anyNamed('programId'),
        body: anyNamed('body'),
        baseRevision: anyNamed('baseRevision'),
        changeId: anyNamed('changeId'),
      ),
    ).thenAnswer((_) async => template());

    final res = await app.send(
      'PUT',
      '/accounts/s/programs/$program/sessions/$session',
      body: {...body, 'baseRevision': 2},
    );

    expect(res.status, 200);
    final restored =
        verify(
              app.db.restoreSession(
                ownerId: 's',
                actorId: 'u1',
                programId: program,
                body: captureAnyNamed('body'),
                baseRevision: 2,
                changeId: anyNamed('changeId'),
              ),
            ).captured.single
            as TemplateRequest;
    expect(restored.id, session);
    told();
  });

  group('updating copies from the library', () {
    const library = '01900000-0000-7000-8000-000000000010';
    const one = '01900000-0000-7000-8000-000000000011';
    const two = '01900000-0000-7000-8000-000000000012';

    CoachSendContext context({String? student, String? existing}) {
      return (
        version: 2,
        body: <String, dynamic>{'name': 'Plan', 'sessions': const <Object?>[]},
        studentId: student,
        existingProgramId: existing,
        existingVersion: 1,
        studentBusy: false,
      );
    }

    test('a program that isn\'t the coach\'s is a 404', () async {
      when(
        app.db.getCoachSendContext(
          coachId: anyNamed('coachId'),
          id: anyNamed('id'),
          connectionId: anyNamed('connectionId'),
        ),
      ).thenAnswer((_) async => null);

      final res = await app.send(
        'POST',
        '/library-programs/$library/update',
        body: {
          'connectionIds': [one],
        },
      );

      expect(res.status, 404);
    });

    test('says, per client, who they no longer coach and who never got it, and writes nothing', () async {
      when(
        app.db.getCoachSendContext(coachId: anyNamed('coachId'), id: anyNamed('id'), connectionId: one),
      ).thenAnswer((_) async => context());
      when(
        app.db.getCoachSendContext(coachId: anyNamed('coachId'), id: anyNamed('id'), connectionId: two),
      ).thenAnswer((_) async => context(student: 's'));

      final res = await app.send(
        'POST',
        '/library-programs/$library/update',
        body: {
          'connectionIds': [one, two],
        },
      );

      expect(res.status, 200);
      final deliveries = ProgramDeliveries.fromJson(jsonDecode(res.body) as Map).deliveries;
      expect(
        [for (final each in deliveries) (each.connectionId, each.delivered, each.reason)],
        [
          (one, false, 'not_coaching'),
          (two, false, 'not_sent'),
        ],
      );
      verifyNever(
        app.db.getCopyAccess(
          coachId: anyNamed('coachId'),
          studentId: anyNamed('studentId'),
          programId: anyNamed('programId'),
        ),
      );
    });
  });

  group('plans', () {
    const workout = '01900000-0000-7000-8000-000000000020';
    final plan = {
      'exercises': [
        {
          'sets': [
            {'weight': 100, 'setId': '01900000-0000-7000-8000-000000000021'},
          ],
        },
      ],
    };

    void stubSavePlan() {
      when(
        app.db.savePlan(
          userId: anyNamed('userId'),
          workoutId: anyNamed('workoutId'),
          plan: anyNamed('plan'),
          loggedBy: anyNamed('loggedBy'),
        ),
      ).thenAnswer((_) async {});
    }

    test('a coach saves one on the student\'s workout, as the one who logged it', () async {
      when(app.db.canLogFor(coachId: anyNamed('coachId'), studentId: anyNamed('studentId')))
          .thenAnswer((_) async => true);
      stubSavePlan();

      final res = await app.send('PUT', '/accounts/s/workouts/$workout/plan', body: {'plan': plan});

      expect(res.status, 204);
      verify(app.db.savePlan(userId: 's', workoutId: workout, plan: plan, loggedBy: 'u1')).called(1);
    });

    test('a person saves one on their own workout, logged by nobody else', () async {
      stubSavePlan();

      final res = await app.send('PUT', '/workouts/$workout/plan', body: {'plan': plan});

      expect(res.status, 204);
      verify(app.db.savePlan(userId: 'u1', workoutId: workout, plan: plan, loggedBy: null)).called(1);
    });

    test('a plan that isn\'t one is refused before anything is saved', () async {
      final res = await app.send(
        'PUT',
        '/workouts/$workout/plan',
        body: {
          'plan': {'exercises': 'all of them'},
        },
      );

      expect(res.status, 400);
      expect(res.body, contains('invalid_plan'));
      verifyNever(
        app.db.savePlan(
          userId: anyNamed('userId'),
          workoutId: anyNamed('workoutId'),
          plan: anyNamed('plan'),
          loggedBy: anyNamed('loggedBy'),
        ),
      );
    });

    test('a coach reads a student\'s plan through what they can read', () async {
      when(
        app.db.getPlan(readerId: anyNamed('readerId'), ownerId: anyNamed('ownerId'), workoutId: anyNamed('workoutId')),
      ).thenAnswer((_) async => plan);

      final res = await app.send('GET', '/accounts/s/workouts/$workout/plan');

      expect(res.status, 200);
      expect(WorkoutPlan.fromJson(jsonDecode(res.body) as Map).plan, plan);
      verify(app.db.getPlan(readerId: 'u1', ownerId: 's', workoutId: workout)).called(1);
    });

    test('a plan there is none of, or past what they can read, is a 404', () async {
      when(
        app.db.getPlan(readerId: anyNamed('readerId'), ownerId: anyNamed('ownerId'), workoutId: anyNamed('workoutId')),
      ).thenAnswer((_) async => null);

      final res = await app.send('GET', '/accounts/s/workouts/$workout/plan');

      expect(res.status, 404);
    });
  });
}
