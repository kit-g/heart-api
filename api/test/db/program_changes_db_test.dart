@Tags(['db'])
library;

import 'package:heart/inputs/inputs.dart';
import 'package:heart/middleware/database.dart';
import 'package:heart/middleware/events.dart';
import 'package:heart/globals/config.dart';
import 'package:heart/models/errors.dart';
import 'package:heart/models/program_copy.dart';
import 'package:heart/routes/coach_library.dart';
import 'package:heart/routes/program_changes.dart' as routes;
import 'package:heart/globals/globals.dart';
import 'package:heart_models/heart_models.dart';
import 'package:mockito/mockito.dart';
import 'package:relic/relic.dart';
import 'package:test/test.dart';

import '../helpers/request.dart';
import '../mocks.mocks.dart';
import 'db_test_utility.dart';

/// Two people on one copy, through what the routes call.
void main() {
  final h = _Harness();

  setUpAll(h.setupDatabase);
  tearDownAll(h.teardownDatabase);

  late String exercise;
  setUpAll(() async => exercise = await h.seedGlobalExercise());

  Map<String, dynamic> session(String name, {double weight = 100}) => {
    'name': name,
    'exercises': [
      {
        'exercise': {'id': exercise},
        'sets': [
          {'weight': weight, 'reps': 5},
        ],
      },
    ],
  };

  Future<({String coach, String student, String connection, String library, String program, List<String> sessions})>
  sent({int sessions = 2}) async {
    final (coach, student) = (await h.seedProfile(), await h.seedProfile());
    await h.exec(
      '''
      INSERT INTO connections (initiator_id, target_id, initiator_role, target_role, domain, status, accepted_at)
      VALUES (@c, @s, 'COACH', 'STUDENT', 'fitness', 'active', '2020-01-01Z')
      ''',
      {'c': coach, 's': student},
    );
    final connection = (await h.db.getConnections(coach)).single.connectionId!;
    final library = uuidV7();
    await h.db.saveCoachProgram(
      coachId: coach,
      id: library,
      name: 'Plan',
      body: withRowIds({
        'name': 'Plan',
        'sessions': [for (var i = 0; i < sessions; i++) session('Day $i')],
      }),
    );
    final req = bareRequest()
      ..coachLibraryService = h.db
      ..programService = h.db;
    final delivery = await deliverCoachProgram(req, coachId: coach, id: library, connectionId: connection);
    final program = await h.db.getProgram(userId: student, programId: delivery.programId!);
    return (
      coach: coach,
      student: student,
      connection: connection,
      library: library,
      program: program.id!,
      sessions: program.sessions,
    );
  }

  TemplateRequest edit(String student, String name, {double weight = 100}) {
    return TemplateUpdateIn.fromJson(session(name, weight: weight), userId: student).request;
  }

  Future<Program> copy(String student, String program) => h.db.getProgram(userId: student, programId: program);

  // The history stops short of any transaction still running, and the other suites
  // sharing this database keep some running: wait for the horizon to pass.
  Future<List<ProgramChange>> history(String student, String program, {int count = 1}) async {
    for (var i = 0; ; i++) {
      final changes = await h.db.getProgramChanges(ownerId: student, programId: program);
      if (changes.length >= count || i == 50) return changes;
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
  }

  Future<String> sessionNamed(String student, List<String> sessions, String name) async {
    for (final id in sessions) {
      if ((await h.db.getTemplate(userId: student, templateId: id)).name == name) return id;
    }
    throw StateError('no session named $name');
  }

  group('revisions', () {
    test('a session of a person\'s own program is none of this', () async {
      final me = await h.seedProfile();
      final (own, _) = await h.db.createProgramOrExisting(
        userId: me,
        program: Program(id: uuidV7(), name: 'Mine'),
        sessions: const [],
      );
      final written = await h.db.writeProgramFields(
        ownerId: me,
        actorId: me,
        programId: own.id!,
        program: Program(name: 'Other'),
      );
      expect(written, isNull);
      expect(await h.db.writeSession(ownerId: me, actorId: me, sessionId: uuidV7(), body: edit(me, 'x')), isNull);
    });

    test('a change records who, what and how it stood, and the revision moves', () async {
      final c = await sent();
      final first = await sessionNamed(c.student, c.sessions, 'Day 0');

      await h.db.writeSession(
        ownerId: c.student,
        actorId: c.coach,
        sessionId: first,
        body: edit(c.student, 'Heavier', weight: 110),
        baseRevision: 0,
      );

      expect((await copy(c.student, c.program)).sessionRevisions[first], 1);
      final change = (await history(c.student, c.program)).single;
      expect(change.actorId, c.coach);
      expect(change.kind, 'edit');
      expect(change.sessionId, first);
      expect(change.before?['name'], 'Day 0');
      expect(change.after?['name'], 'Heavier');
      expect(change.stale, isFalse);
    });

    test('someone else changing this session since your base is a conflict', () async {
      final c = await sent();
      final first = c.sessions.first;
      await h.db.writeSession(
        ownerId: c.student,
        actorId: c.coach,
        sessionId: first,
        body: edit(c.student, 'Coach'),
        baseRevision: 0,
      );

      await expectLater(
        h.db.writeSession(
          ownerId: c.student,
          actorId: c.student,
          sessionId: first,
          body: edit(c.student, 'Student'),
          baseRevision: 0,
        ),
        throwsA(isA<Conflict>().having((e) => e.code, 'code', 'program_changed')),
      );
      expect((await h.db.getTemplate(userId: c.student, templateId: first)).name, 'Coach');
    });

    test('a coach changing Monday does not stop the student changing Thursday', () async {
      final c = await sent();
      await h.db.writeSession(
        ownerId: c.student,
        actorId: c.coach,
        sessionId: c.sessions.first,
        body: edit(c.student, 'Monday'),
        baseRevision: 0,
      );
      final thursday = await h.db.writeSession(
        ownerId: c.student,
        actorId: c.student,
        sessionId: c.sessions.last,
        body: edit(c.student, 'Thursday'),
        baseRevision: 0,
      );
      expect(thursday?.name, 'Thursday');
    });

    test('your own changes since your base do not conflict, so two queued edits land', () async {
      final c = await sent();
      for (final name in ['First', 'Second']) {
        await h.db.writeSession(
          ownerId: c.student,
          actorId: c.student,
          sessionId: c.sessions.first,
          body: edit(c.student, name),
          baseRevision: 0,
        );
      }
      expect((await h.db.getTemplate(userId: c.student, templateId: c.sessions.first)).name, 'Second');
    });

    test('a retried save is one change', () async {
      final c = await sent();
      final change = uuidV7();
      for (var i = 0; i < 2; i++) {
        await h.db.writeSession(
          ownerId: c.student,
          actorId: c.student,
          sessionId: c.sessions.first,
          body: edit(c.student, 'Once'),
          baseRevision: 0,
          changeId: change,
        );
      }
      expect(await history(c.student, c.program), hasLength(1));
    });

    test('an old build is accepted, marked stale, and what it overwrote is kept', () async {
      final c = await sent();
      await h.db.writeSession(
        ownerId: c.student,
        actorId: c.coach,
        sessionId: c.sessions.first,
        body: edit(c.student, 'Coach'),
        baseRevision: 0,
      );

      final written = await h.db.writeSession(
        ownerId: c.student,
        actorId: c.student,
        sessionId: c.sessions.first,
        body: edit(c.student, 'Old build'),
      );
      expect(written?.name, 'Old build');
      final last = (await history(c.student, c.program, count: 2)).last;
      expect(last.stale, isTrue);
      expect(last.before?['name'], 'Coach');
    });
  });

  group('putting things back', () {
    late MockEventPublisher events;
    late MockAppConfig config;

    Request request(String user) {
      events = MockEventPublisher();
      config = MockAppConfig();
      when(config.eventsQueueUrl).thenReturn('https://sqs.test/events');
      when(events.publish(queueUrl: anyNamed('queueUrl'), message: anyNamed('message'))).thenAnswer((_) async {});
      return bareRequest()
        ..user = User(id: user)
        ..config = config
        ..events = events
        ..programChangeService = h.db
        ..programService = h.db
        ..coachLibraryService = h.db
        ..templatesService = h.db;
    }

    test('a deleted session comes back under its own id, with its workouts and its position', () async {
      final c = await sent();
      final first = c.sessions.first;
      final workout = await h.insertId(
        '''
        INSERT INTO workouts (user_id, name, started_at, completed_at, template_id, program_id)
        VALUES (@u, 'Done', now(), now(), @t::uuid, @p::uuid)
        RETURNING id
        ''',
        {'u': c.student, 't': first, 'p': c.program},
      );

      await h.db.removeSession(ownerId: c.student, actorId: c.student, sessionId: first);
      final cleared = await h.exec('SELECT template_id FROM workouts WHERE id = @w::uuid', {'w': workout});
      expect(cleared.first[0], isNull);

      final change = (await history(c.student, c.program)).single;
      expect(change.kind, 'delete');
      await expectLater(
        routes.revertById(request(c.coach), ownerId: c.student, programId: c.program, changeId: change.id),
        throwsA(isA<NoContent>()),
      );

      expect((await copy(c.student, c.program)).sessions, contains(first));
      final linked = await h.exec('SELECT template_id FROM workouts WHERE id = @w::uuid', {'w': workout});
      expect(linked.first[0].toString(), first);
      expect((await history(c.student, c.program, count: 2)).last.kind, 'revert');
    });

    test('an edit goes back to how it stood, as a change like any other', () async {
      final c = await sent();
      final first = c.sessions.first;
      await h.db.writeSession(
        ownerId: c.student,
        actorId: c.student,
        sessionId: first,
        body: edit(c.student, 'Mine'),
        baseRevision: 0,
      );
      final change = (await history(c.student, c.program)).single;

      await expectLater(
        routes.revertById(request(c.coach), ownerId: c.student, programId: c.program, changeId: change.id),
        throwsA(isA<NoContent>()),
      );
      expect((await h.db.getTemplate(userId: c.student, templateId: first)).name, 'Day 0');
      expect(await history(c.student, c.program, count: 2), hasLength(2));
    });

    test('bringing a copy up to date keeps the ids a student trained, and their week', () async {
      final c = await sent();
      final first = await sessionNamed(c.student, c.sessions, 'Day 0');
      final other = await sessionNamed(c.student, c.sessions, 'Day 1');
      await h.exec(
        '''
        INSERT INTO workouts (user_id, name, started_at, completed_at, template_id, program_id)
        VALUES (@u, 'Done', now(), now(), @t::uuid, @p::uuid)
        ''',
        {'u': c.student, 't': first, 'p': c.program},
      );
      final library = await h.db.getCoachProgram(coachId: c.coach, id: c.library);
      final body = library.body!;
      final dayZero = (body['sessions'] as List).cast<Map>().firstWhere((each) => each['name'] == 'Day 0');
      await h.db.saveCoachProgram(
        coachId: c.coach,
        id: c.library,
        name: 'Plan',
        body: withRowIds({
          ...body,
          'sessions': [
            {...dayZero, 'name': 'Day 0, heavier'},
            session('A new day'),
          ],
        }),
      );

      final delivery = await routes.updateCopyFor(request(c.coach), id: c.library, connectionId: c.connection);
      expect(delivery.delivered, isTrue, reason: '${delivery.reason}');

      final read = await copy(c.student, c.program);
      expect(read.sessions, contains(first));
      expect(read.sessions, isNot(contains(other)), reason: 'the session no longer in the program goes');
      expect(read.sessions, hasLength(2));
      expect((await h.db.getTemplate(userId: c.student, templateId: first)).name, 'Day 0, heavier');
      final marks = await h.db.getProgramMarks(userId: c.student, programId: c.program);
      expect(marks.single.templateId, first, reason: 'the workout still names its session');

      final holders = await h.db.getCoachProgramHolders(coachId: c.coach, id: c.library);
      expect(holders.single.version, 2);
      final changes = await history(c.student, c.program, count: 4);
      expect(changes.every((change) => change.kind == 'library_update'), isTrue);
    });
  });

  group('access', () {
    test('a coach reads and writes across the live connection, and it ends with it', () async {
      final c = await sent();
      var access = await h.db.getCopyAccess(coachId: c.coach, studentId: c.student, programId: c.program);
      expect(access, (readable: true, writable: true));

      await h.db.changeConnectionStatus(
        actorId: c.student,
        targetId: c.coach,
        role: .student,
        domain: .fitness,
        newStatus: .paused,
      );
      access = await h.db.getCopyAccess(coachId: c.coach, studentId: c.student, programId: c.program);
      expect(access, (readable: true, writable: false));

      await h.db.deleteConnection(actorId: c.student, targetId: c.coach, role: .student, domain: .fitness);
      access = await h.db.getCopyAccess(coachId: c.coach, studentId: c.student, programId: c.program);
      expect(access, (readable: false, writable: false));
      expect(await h.db.getCopies(coachId: c.coach, studentId: c.student), isEmpty);
    });

    test('a block closes it, and another coach never had it', () async {
      final c = await sent();
      final other = await h.seedProfile();
      var access = await h.db.getCopyAccess(coachId: other, studentId: c.student, programId: c.program);
      expect(access, (readable: false, writable: false));

      await h.exec('INSERT INTO blocks (blocker_id, blocked_id) VALUES (@s, @c)', {'s': c.student, 'c': c.coach});
      access = await h.db.getCopyAccess(coachId: c.coach, studentId: c.student, programId: c.program);
      expect(access, (readable: false, writable: false));
    });

    test('what a coach counts leaves out what is hidden', () async {
      final c = await sent();
      final workout = await h.insertId(
        '''
        INSERT INTO workouts (user_id, name, started_at, completed_at, template_id, program_id)
        VALUES (@u, 'Done', now(), now(), @t::uuid, @p::uuid)
        RETURNING id
        ''',
        {'u': c.student, 't': c.sessions.first, 'p': c.program},
      );
      Future<int> seen() async {
        final marks = await h.db.getVisibleMarks(readerId: c.coach, ownerId: c.student, programId: c.program);
        return marks.length;
      }

      expect(await seen(), 1);
      await h.db.hideWorkout(userId: c.student, workoutId: workout);
      expect(await seen(), 0);
      expect(await h.db.getProgramMarks(userId: c.student, programId: c.program), hasLength(1));
    });
  });

  group('what was asked', () {
    test('the first plan stays, and a coach reads it only under the read policy', () async {
      final c = await sent();
      final workout = await h.seedWorkout(userId: c.student, start: DateTime.utc(2026), end: DateTime.utc(2026));
      await h.db.savePlan(userId: c.student, workoutId: workout, plan: {'week': 1});
      await h.db.savePlan(userId: c.student, workoutId: workout, plan: {'week': 2});

      expect(await h.db.getPlan(readerId: c.coach, ownerId: c.student, workoutId: workout), {'week': 1});

      await h.db.hideWorkout(userId: c.student, workoutId: workout);
      expect(await h.db.getPlan(readerId: c.coach, ownerId: c.student, workoutId: workout), isNull);
      expect(await h.db.getPlan(readerId: c.student, ownerId: c.student, workoutId: workout), {'week': 1});
    });

    test('only on your own workout', () async {
      final (me, other) = (await h.seedProfile(), await h.seedProfile());
      final workout = await h.seedWorkout(userId: other);
      await expectLater(h.db.savePlan(userId: me, workoutId: workout, plan: {'x': 1}), throwsA(isA<NotFound>()));
    });
  });
}

class _Harness extends DatabaseTestBase;
