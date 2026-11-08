@Tags(['db'])
library;

import 'package:heart/inputs/inputs.dart';
import 'package:heart/middleware/database.dart';
import 'package:heart/middleware/events.dart';
import 'package:heart/globals/config.dart';
import 'package:heart/models/changes.dart';
import 'package:heart/models/errors.dart';
import 'package:heart/models/program_copy.dart';
import 'package:heart/routes/coach_library.dart';
import 'package:heart/routes/program_changes.dart' as routes;
import 'package:heart/globals/globals.dart';
import 'package:heart_models/heart_models.dart';
import 'package:mockito/mockito.dart';
import 'package:relic/relic.dart';
import 'package:postgres/postgres.dart' show Sql;
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

    // The statements have to overlap: both queue behind a lock this test holds, so each
    // starts before the other has written. A check in the statement that takes the lock
    // would see neither, and the second would overwrite the first.
    test('of two saves waiting at once from one base, the second is told', () async {
      final c = await sent();
      final first = c.sessions.first;

      late Future<List<String>> saves;
      await h.pool.runTx((tx) async {
        await tx.execute(
          Sql.named('SELECT id FROM templates WHERE id = @id::uuid FOR UPDATE'),
          parameters: {'id': first},
        );
        saves = Future.wait([
          for (final (actor, name) in [(c.coach, 'Coach'), (c.student, 'Student')])
            h.db
                .writeSession(
                  ownerId: c.student,
                  actorId: actor,
                  sessionId: first,
                  body: edit(c.student, name),
                  baseRevision: 0,
                )
                .then<String>((_) => 'saved', onError: (Object e) => (e as Conflict).code),
        ]);
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });

      final outcomes = await saves;
      expect(outcomes.where((outcome) => outcome == 'saved'), hasLength(1));
      expect(outcomes.where((outcome) => outcome == 'program_changed'), hasLength(1));
    });

    test('the same for a program\'s own fields', () async {
      final c = await sent();

      late Future<List<String>> saves;
      await h.pool.runTx((tx) async {
        await tx.execute(
          Sql.named('SELECT id FROM programs WHERE id = @id::uuid FOR UPDATE'),
          parameters: {'id': c.program},
        );
        saves = Future.wait([
          for (final (actor, name) in [(c.coach, 'Coach'), (c.student, 'Student')])
            h.db
                .writeProgramFields(
                  ownerId: c.student,
                  actorId: actor,
                  programId: c.program,
                  program: Program(name: name),
                  baseRevision: 0,
                )
                .then<String>((_) => 'saved', onError: (Object e) => (e as Conflict).code),
        ]);
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });

      final outcomes = await saves;
      expect(outcomes.where((outcome) => outcome == 'saved'), hasLength(1));
      expect(outcomes.where((outcome) => outcome == 'program_changed'), hasLength(1));
    });

    test('order goes by the transaction id as a number, across a digit boundary', () async {
      final c = await sent();
      await h.db.writeSession(
        ownerId: c.student,
        actorId: c.student,
        sessionId: c.sessions.first,
        body: edit(c.student, 'Older'),
        baseRevision: 0,
      );
      await h.db.writeSession(
        ownerId: c.student,
        actorId: c.student,
        sessionId: c.sessions.first,
        body: edit(c.student, 'Newer'),
        baseRevision: 1,
      );
      final saved = await history(c.student, c.program, count: 2);
      await h.exec("UPDATE program_changes SET xid = '999'::xid8 WHERE id = @id::uuid", {'id': saved.first.id});
      await h.exec("UPDATE program_changes SET xid = '1000'::xid8 WHERE id = @id::uuid", {'id': saved.last.id});

      final changes = await h.db.getProgramChanges(ownerId: c.student, programId: c.program);
      expect(changes.map((change) => change.after?['name']), ['Older', 'Newer']);
    });

    test('a coach cannot reach a session through a program it isn\'t in', () async {
      final c = await sent();
      // the student's own template, which a workout's templateId could give away
      final own = await h.insertId(
        'INSERT INTO templates (user_id, name, order_index) VALUES (@u, @n, 0) RETURNING id',
        {'u': c.student, 'n': 'Private'},
      );
      final other = await sent();

      expect(
        await h.db.writeSession(
          ownerId: c.student,
          actorId: c.coach,
          sessionId: other.sessions.first,
          programId: c.program,
          body: edit(c.student, 'Taken'),
        ),
        isNull,
      );
      expect(
        await h.db.removeSession(
          ownerId: c.student,
          actorId: c.coach,
          sessionId: c.sessions.first,
          programId: other.program,
        ),
        isNull,
      );
      await expectLater(
        h.db.restoreSession(
          ownerId: c.student,
          actorId: c.coach,
          programId: c.program,
          body: TemplateCreateIn.fromJson({...session('Taken'), 'id': own}, userId: c.student).request,
        ),
        throwsA(isA<Forbidden>().having((e) => e.code, 'code', 'id_taken')),
      );
      final row = await h.exec('SELECT name, assigned_by, program_id FROM templates WHERE id = @t::uuid', {'t': own});
      expect(row.first.toColumnMap(), {'name': 'Private', 'assigned_by': null, 'program_id': null});
    });

    test('a session put back carries on from its history, so nobody is locked out', () async {
      final c = await sent();
      final first = c.sessions.first;
      await h.db.writeSession(
        ownerId: c.student,
        actorId: c.coach,
        sessionId: first,
        body: edit(c.student, 'One'),
        baseRevision: 0,
      );
      await h.db.writeSession(
        ownerId: c.student,
        actorId: c.coach,
        sessionId: first,
        body: edit(c.student, 'Two'),
        baseRevision: 1,
      );
      await h.db.removeSession(ownerId: c.student, actorId: c.coach, sessionId: first);
      await h.db.restoreSession(
        ownerId: c.student,
        actorId: c.coach,
        programId: c.program,
        body: TemplateCreateIn.fromJson({...session('Back'), 'id': first}, userId: c.student).request,
        kind: 'revert',
      );

      final revision = (await copy(c.student, c.program)).sessionRevisions[first]!;
      expect(revision, 4);
      final saved = await h.db.writeSession(
        ownerId: c.student,
        actorId: c.student,
        sessionId: first,
        body: edit(c.student, 'Mine'),
        baseRevision: revision,
      );
      expect(saved?.name, 'Mine', reason: 'a save from what they just read goes through');
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
      final first = await sessionNamed(c.student, c.sessions, 'Day 0');
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
      final changes = await history(c.student, c.program, count: 3);
      expect(changes.every((change) => change.kind == 'library_update'), isTrue);
    });

    Future<void> saveVersion(({String coach, String library}) c, List<Map<String, dynamic>> sessions) async {
      final body = (await h.db.getCoachProgram(coachId: c.coach, id: c.library)).body!;
      await h.db.saveCoachProgram(
        coachId: c.coach,
        id: c.library,
        name: 'Plan',
        body: withRowIds({...body, 'sessions': sessions}),
      );
    }

    Future<List<Map<String, dynamic>>> librarySessions(({String coach, String library}) c) async {
      final body = (await h.db.getCoachProgram(coachId: c.coach, id: c.library)).body!;
      return [for (final each in body['sessions'] as List) (each as Map).cast<String, dynamic>()];
    }

    test('a note the library drops goes from the copy too', () async {
      final c = await sent(sessions: 1);
      final [day] = await librarySessions((coach: c.coach, library: c.library));
      await saveVersion(
        (coach: c.coach, library: c.library),
        [
          {...day, 'note': 'Go easy'},
        ],
      );
      await routes.updateCopyFor(request(c.coach), id: c.library, connectionId: c.connection);
      expect((await h.db.getTemplate(userId: c.student, templateId: c.sessions.single)).note, 'Go easy');

      await saveVersion(
        (coach: c.coach, library: c.library),
        [
          {...day}..remove('note'),
        ],
      );
      final delivery = await routes.updateCopyFor(request(c.coach), id: c.library, connectionId: c.connection);
      expect(delivery.delivered, isTrue, reason: '${delivery.reason}');
      expect((await h.db.getTemplate(userId: c.student, templateId: c.sessions.single)).note, isNull);
    });

    test('a copy already up to date is left as the student made it', () async {
      final c = await sent(sessions: 1);
      final [day] = await librarySessions((coach: c.coach, library: c.library));
      await saveVersion(
        (coach: c.coach, library: c.library),
        [
          {...day, 'name': 'Version two'},
        ],
      );
      await routes.updateCopyFor(request(c.coach), id: c.library, connectionId: c.connection);
      await h.db.writeSession(
        ownerId: c.student,
        actorId: c.student,
        sessionId: c.sessions.single,
        body: edit(c.student, 'Mine'),
        baseRevision: 1,
      );

      final again = await routes.updateCopyFor(request(c.coach), id: c.library, connectionId: c.connection);
      expect(again.delivered, isTrue);
      expect((await h.db.getTemplate(userId: c.student, templateId: c.sessions.single)).name, 'Mine');
    });

    test('a session a version drops and a later one brings back keeps its id', () async {
      final c = await sent();
      final sessions = await librarySessions((coach: c.coach, library: c.library));
      final first = await sessionNamed(c.student, c.sessions, 'Day 0');
      await saveVersion((coach: c.coach, library: c.library), [sessions.last]);
      await routes.updateCopyFor(request(c.coach), id: c.library, connectionId: c.connection);
      expect((await copy(c.student, c.program)).sessions, isNot(contains(first)));

      await saveVersion((coach: c.coach, library: c.library), sessions);
      await routes.updateCopyFor(request(c.coach), id: c.library, connectionId: c.connection);
      expect((await copy(c.student, c.program)).sessions, contains(first));
    });

    test('a client whose copy can\'t take the version is reported, not a failed request', () async {
      final c = await sent(sessions: 1);
      // a version saved under rules this server no longer holds
      await h.exec(
        '''
        WITH _next AS (
          UPDATE library_programs SET version = version + 1 WHERE id = @l::uuid RETURNING id, version
        )
        INSERT INTO library_program_versions (library_program_id, version, body)
        SELECT id, version, '{"name": ""}'::jsonb FROM _next
        ''',
        {'l': c.library},
      );
      final delivery = await routes.updateCopyFor(request(c.coach), id: c.library, connectionId: c.connection);
      expect(delivery.delivered, isFalse);
      expect(delivery.reason, 'bad_request');
    });

    test('an update across a connection the copy didn\'t come through writes nothing', () async {
      final c = await sent(sessions: 1);
      await h.exec('UPDATE programs SET connection_id = NULL WHERE id = @p::uuid', {'p': c.program});
      final [day] = await librarySessions((coach: c.coach, library: c.library));
      await saveVersion(
        (coach: c.coach, library: c.library),
        [
          {...day, 'name': 'Changed'},
        ],
      );
      final delivery = await routes.updateCopyFor(request(c.coach), id: c.library, connectionId: c.connection);
      expect(delivery.delivered, isFalse);
      expect((await h.db.getTemplate(userId: c.student, templateId: c.sessions.single)).name, 'Day 0');
    });

    test('putting an edit back clears a note it added', () async {
      final c = await sent(sessions: 1);
      await h.db.writeSession(
        ownerId: c.student,
        actorId: c.student,
        sessionId: c.sessions.single,
        body: TemplateUpdateIn.fromJson({...session('Day 0'), 'note': 'Mine'}, userId: c.student).request,
        baseRevision: 0,
      );
      final change = (await history(c.student, c.program)).single;
      await expectLater(
        routes.revertById(request(c.coach), ownerId: c.student, programId: c.program, changeId: change.id),
        throwsA(isA<NoContent>()),
      );
      expect((await h.db.getTemplate(userId: c.student, templateId: c.sessions.single)).note, isNull);
    });

    test('putting back a session the other person has since changed is a conflict', () async {
      final c = await sent(sessions: 0);
      final added = uuidV7();
      await h.db.restoreSession(
        ownerId: c.student,
        actorId: c.coach,
        programId: c.program,
        body: TemplateCreateIn.fromJson({...session('Added'), 'id': added}, userId: c.student).request,
      );
      await h.db.writeSession(
        ownerId: c.student,
        actorId: c.student,
        sessionId: added,
        body: edit(c.student, 'Trained it'),
        baseRevision: 1,
      );
      final create = (await history(c.student, c.program, count: 2)).first;
      expect(create.kind, 'create');
      await expectLater(
        routes.revertById(request(c.coach), ownerId: c.student, programId: c.program, changeId: create.id),
        throwsA(isA<Conflict>()),
      );
      expect((await copy(c.student, c.program)).sessions, contains(added));
    });
  });

  group('what a write does', () {
    test('a folder that is not the student\'s refuses the write, and nothing moves', () async {
      final c = await sent(sessions: 1);
      await expectLater(
        h.db.writeSession(
          ownerId: c.student,
          actorId: c.coach,
          sessionId: c.sessions.single,
          body: TemplateUpdateIn.fromJson({...session('Filed'), 'folderId': uuidV7()}, userId: c.student).request,
          baseRevision: 0,
        ),
        throwsA(isA<NotFound>()),
      );
      expect((await copy(c.student, c.program)).sessionRevisions[c.sessions.single] ?? 0, 0);
      expect((await h.db.getTemplate(userId: c.student, templateId: c.sessions.single)).name, 'Day 0');
    });

    test('a write that changes nothing moves no revision, so the other side isn\'t stopped', () async {
      final c = await sent(sessions: 1);
      // an upsync replaying the session as it stands, ids and all
      final standing = await h.db.getTemplate(userId: c.student, templateId: c.sessions.single);
      final written = await h.db.writeSession(
        ownerId: c.student,
        actorId: c.student,
        sessionId: c.sessions.single,
        body: TemplateUpdateIn.fromJson(standing.toMap(), userId: c.student).request,
      );
      expect(written?.name, 'Day 0');
      expect((await copy(c.student, c.program)).sessionRevisions[c.sessions.single] ?? 0, 0);
      final coach = await h.db.writeSession(
        ownerId: c.student,
        actorId: c.coach,
        sessionId: c.sessions.single,
        body: edit(c.student, 'Coach'),
        baseRevision: 0,
      );
      expect(coach?.name, 'Coach');
    });

    test('a coach\'s words on a session the student added are quoted as the coach\'s', () async {
      final c = await sent(sessions: 1);
      await h.exec('UPDATE templates SET assigned_by = NULL WHERE id = @t::uuid', {'t': c.sessions.single});
      await h.db.writeSession(
        ownerId: c.student,
        actorId: c.coach,
        sessionId: c.sessions.single,
        body: edit(c.student, 'Ignore what you were told'),
        baseRevision: 0,
      );
      final row = await h.exec('SELECT assigned_by FROM templates WHERE id = @t::uuid', {'t': c.sessions.single});
      expect(row.first[0], c.coach);
    });

    test('a coach editing over a base a deletion has passed is a conflict, not a resurrection', () async {
      final c = await sent(sessions: 1);
      final gone = c.sessions.single;
      await h.db.removeSession(ownerId: c.student, actorId: c.student, sessionId: gone);
      await expectLater(
        h.db.restoreSession(
          ownerId: c.student,
          actorId: c.coach,
          programId: c.program,
          body: TemplateCreateIn.fromJson({...session('Coach'), 'id': gone}, userId: c.student).request,
          baseRevision: 0,
        ),
        throwsA(isA<Conflict>()),
      );
      expect((await copy(c.student, c.program)).sessions, isEmpty);
    });

    test('a retried create is one change', () async {
      final c = await sent(sessions: 0);
      final added = uuidV7();
      final change = uuidV7();
      await h.db.restoreSession(
        ownerId: c.student,
        actorId: c.coach,
        programId: c.program,
        body: TemplateCreateIn.fromJson({...session('New'), 'id': added}, userId: c.student).request,
        changeId: change,
      );
      final retried = await h.db.writeSession(
        ownerId: c.student,
        actorId: c.coach,
        sessionId: added,
        programId: c.program,
        body: edit(c.student, 'New'),
        baseRevision: 0,
        changeId: change,
      );
      expect(retried?.name, 'New');
      expect(await history(c.student, c.program), hasLength(1));
    });

    test('a snapshot keeps what was said, not who said it', () async {
      final c = await sent(sessions: 1);
      await h.db.writeSession(
        ownerId: c.student,
        actorId: c.student,
        sessionId: c.sessions.single,
        body: edit(c.student, 'Mine'),
        baseRevision: 0,
      );
      final change = (await history(c.student, c.program)).single;
      expect(change.before?['name'], 'Day 0');
      expect(change.before?.containsKey('assignedBy'), isFalse);
    });

    test('a cursor from past the counter, as after a move, is refused', () async {
      final c = await sent(sessions: 0);
      final ahead = ChangeCursor(xid: '999999999999', id: uuidV7()).toString();
      await expectLater(
        h.db.getProgramChanges(ownerId: c.student, programId: c.program, since: ahead),
        throwsA(isA<BadRequest>().having((e) => e.code, 'code', 'stale_cursor')),
      );
    });

    test('a program that isn\'t the reader\'s is missing, not one without history', () async {
      final c = await sent(sessions: 0);
      for (final (owner, program) in [(c.coach, c.program), (c.student, uuidV7())]) {
        await expectLater(
          h.db.getProgramChanges(ownerId: owner, programId: program),
          throwsA(isA<NotFound>().having((e) => e.code, 'code', 'program_not_found')),
        );
      }
    });

    test('a former coach isn\'t told of the student\'s changes', () async {
      final c = await sent(sessions: 0);
      expect(await h.db.otherSideOf(actorId: c.student, programId: c.program), c.coach);
      await h.db.deleteConnection(actorId: c.student, targetId: c.coach, role: .student, domain: .fitness);
      expect(await h.db.otherSideOf(actorId: c.student, programId: c.program), isNull);
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
