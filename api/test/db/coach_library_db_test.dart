@Tags(['db'])
library;

import 'package:heart/middleware/database.dart';
import 'package:heart/models/errors.dart';
import 'package:heart/models/program_copy.dart';
import 'package:heart/routes/coach_library.dart';
import 'package:heart_models/heart_models.dart';
import 'package:test/test.dart';

import '../helpers/request.dart';
import 'db_test_utility.dart';

/// The queries behind a coach's library, and sending end to end through what the
/// route calls.
void main() {
  final h = _Harness();

  setUpAll(h.setupDatabase);
  tearDownAll(h.teardownDatabase);

  Map<String, dynamic> body(String name) => withRowIds({
    'name': name,
    'sessions': [
      {'name': 'Monday', 'exercises': <Object?>[]},
    ],
  });

  Future<(String, String, String)> coaching() async {
    final (coach, student) = (await h.seedProfile(), await h.seedProfile());
    await h.exec(
      '''
      INSERT INTO connections (initiator_id, target_id, initiator_role, target_role, domain, status)
      VALUES (@c, @s, 'COACH', 'STUDENT', 'fitness', 'active')
      ''',
      {'c': coach, 's': student},
    );
    return (coach, student, (await h.db.getConnections(coach)).single.connectionId!);
  }

  group('the library', () {
    test('a save makes a new version, and the old one stays', () async {
      final coach = await h.seedProfile();
      final id = uuidV7();
      final first = await h.db.saveCoachProgram(coachId: coach, id: id, name: 'One', body: body('One'));
      expect(first.version, 1);

      final second = await h.db.saveCoachProgram(coachId: coach, id: id, name: 'Two', body: body('Two'));
      expect(second.version, 2);
      expect((await h.db.getCoachProgram(coachId: coach, id: id)).body?['name'], 'Two');

      final versions = await h.exec(
        'SELECT count(*) FROM library_program_versions WHERE library_program_id = @id::uuid',
        {'id': id},
      );
      expect(versions.first[0], 2);
    });

    test('is kept apart from the coach\'s own programs and templates', () async {
      final coach = await h.seedProfile();
      await h.db.saveCoachProgram(coachId: coach, id: uuidV7(), name: 'One', body: body('One'));
      expect(await h.db.getPrograms(coach), isEmpty);
      final templates = await h.exec('SELECT 1 FROM templates WHERE user_id = @c', {'c': coach});
      expect(templates, isEmpty);
    });

    test('someone else cannot read, change or delete one', () async {
      final (coach, other) = (await h.seedProfile(), await h.seedProfile());
      final id = uuidV7();
      await h.db.saveCoachProgram(coachId: coach, id: id, name: 'One', body: body('One'));

      await expectLater(h.db.getCoachProgram(coachId: other, id: id), throwsA(isA<NotFound>()));
      await expectLater(
        h.db.saveCoachProgram(coachId: other, id: id, name: 'Mine', body: body('Mine')),
        throwsA(isA<Forbidden>().having((e) => e.code, 'code', 'id_taken')),
        reason: 'their id, not a full library',
      );
      await h.db.deleteCoachProgram(coachId: other, id: id);
      expect((await h.db.getCoachProgram(coachId: coach, id: id)).name, 'One');
    });

    test('saving what is already the current version, as a retry does, makes no new one', () async {
      final coach = await h.seedProfile();
      final id = uuidV7();
      final document = body('One');
      await h.db.saveCoachProgram(coachId: coach, id: id, name: 'One', body: document);
      final again = await h.db.saveCoachProgram(coachId: coach, id: id, name: 'One', body: document);
      expect(again.version, 1);
      expect(again.body?['name'], 'One');
      expect((await h.db.saveCoachProgram(coachId: coach, id: id, name: 'Two', body: document)).version, 2);
    });
  });

  group('what a send knows', () {
    test('a student across an active coach row', () async {
      final (coach, student, connection) = await coaching();
      final id = uuidV7();
      await h.db.saveCoachProgram(coachId: coach, id: id, name: 'One', body: body('One'));

      final context = await h.db.getCoachSendContext(coachId: coach, id: id, connectionId: connection);
      expect(context?.studentId, student);
      expect(context?.studentBusy, isFalse);
      expect(context?.existingProgramId, isNull);
    });

    test('nobody across a peer row, a paused one, a block, or someone else\'s', () async {
      final (coach, student, connection) = await coaching();
      final id = uuidV7();
      await h.db.saveCoachProgram(coachId: coach, id: id, name: 'One', body: body('One'));

      Future<String?> reached(String who) async {
        return (await h.db.getCoachSendContext(coachId: coach, id: id, connectionId: who))?.studentId;
      }

      final peer = await h.seedProfile();
      await h.exec(
        '''
        INSERT INTO connections (initiator_id, target_id, initiator_role, target_role, domain, status)
        VALUES (@c, @p, 'PEER', 'PEER', 'general', 'active')
        ''',
        {'c': coach, 'p': peer},
      );
      final peers = (await h.db.getConnections(peer)).single.connectionId!;
      expect(await reached(peers), isNull);

      await h.exec("UPDATE connections SET status = 'paused' WHERE id = @c::uuid", {'c': connection});
      expect(await reached(connection), isNull);
      await h.exec("UPDATE connections SET status = 'active' WHERE id = @c::uuid", {'c': connection});
      expect(await reached(connection), student);

      await h.exec('INSERT INTO blocks (blocker_id, blocked_id) VALUES (@s, @c)', {'s': student, 'c': coach});
      expect(await reached(connection), isNull);

      final (_, _, theirs) = await coaching();
      expect(await reached(theirs), isNull);
    });

    test('nothing for a program that is not the coach\'s', () async {
      final (coach, _, connection) = await coaching();
      expect(await h.db.getCoachSendContext(coachId: coach, id: uuidV7(), connectionId: connection), isNull);
    });
  });

  group('exercises for a student', () {
    test('their own by name, then the library\'s, then a copy', () async {
      final (coach, student, _) = await coaching();
      final global = await h.seedGlobalExercise();
      Future<String> custom(String owner, String name) => h.insertId(
        "INSERT INTO exercises (name, category, target, user_id) VALUES (@n, 'Barbell', 'Chest', @u) RETURNING id",
        {'n': name, 'u': owner},
      );
      final shared = 'Shared ${h.uid('x')}';
      final coachesShared = await custom(coach, shared);
      final studentsShared = await custom(student, shared);
      final onlyCoach = await custom(coach, 'Only ${h.uid('x')}');

      final matched = await h.db.matchExercisesForStudent(
        ids: [global, coachesShared, onlyCoach, uuidV7()],
        coachId: coach,
        studentId: student,
      );

      expect(matched[global], global);
      expect(matched[coachesShared], studentsShared);
      expect(matched[onlyCoach], isNot(onlyCoach));
      expect(matched, hasLength(3), reason: 'an id that is no exercise stays out');
      final owner = await h.exec('SELECT user_id FROM exercises WHERE id = @id::uuid', {'id': matched[onlyCoach]});
      expect(owner.first[0], student);
    });

    // heart-api#395: "Bench" from the coach made a second "Bench" beside the student's "bench"
    test('a name matches whatever its case, and the same spelling wins a tie', () async {
      final (coach, student, _) = await coaching();
      Future<String> custom(String owner, String name) => h.insertId(
        "INSERT INTO exercises (name, category, target, user_id) VALUES (@n, 'Barbell', 'Chest', @u) RETURNING id",
        {'n': name, 'u': owner},
      );
      final name = 'Bench ${h.uid('x')}';
      final coaches = await custom(coach, name);
      final lower = await custom(student, name.toLowerCase());

      expect((await h.db.matchExercisesForStudent(ids: [coaches], coachId: coach, studentId: student))[coaches], lower);
      final copies = await h.exec(
        'SELECT count(*) FROM exercises WHERE user_id = @s AND lower(name) = lower(@n)',
        {'s': student, 'n': name},
      );
      expect(copies.first[0], 1, reason: 'no second exercise for the student');

      final exact = await custom(student, name);
      expect((await h.db.matchExercisesForStudent(ids: [coaches], coachId: coach, studentId: student))[coaches], exact);
    });
  });

  test('someone else\'s private exercise doesn\'t get copied to anyone', () async {
    final (coach, student, _) = await coaching();
    final stranger = await h.seedProfile();
    final name = 'Private ${h.uid('x')}';
    final private = await h.insertId(
      "INSERT INTO exercises (name, category, target, user_id) VALUES (@n, 'Barbell', 'Chest', @u) RETURNING id",
      {'n': name, 'u': stranger},
    );

    final matched = await h.db.matchExercisesForStudent(ids: [private], coachId: coach, studentId: student);

    expect(matched, isEmpty);
    final copied = await h.exec('SELECT 1 FROM exercises WHERE name = @n AND user_id = @s', {'n': name, 's': student});
    expect(copied, isEmpty);
  });

  test('a copy keeps the program a coach\'s, its sessions theirs, and waits if the student is busy', () async {
    final (coach, student, connection) = await coaching();
    final library = uuidV7();
    await h.db.saveCoachProgram(coachId: coach, id: library, name: 'One', body: body('One'));

    final (program, _) = await h.db.createProgramOrExisting(
      userId: student,
      program: Program(id: uuidV7(), name: 'One'),
      sessions: const [],
      copy: (
        coachId: coach,
        connectionId: connection,
        libraryProgramId: library,
        libraryVersion: 1,
        libraryIds: const {'a': 'b'},
        waits: true,
      ),
    );
    final read = await h.db.getProgram(userId: student, programId: program.id!);
    expect(read.coachId, coach);
    expect(read.coachName, 'u_$coach');
    expect(read.waitingSince, isNotNull);

    await expectLater(h.db.startProgram(userId: coach, programId: program.id!), throwsA(isA<NotFound>()));
    expect((await h.db.getProgram(userId: student, programId: program.id!)).waitingSince, isNotNull);
    await h.db.startProgram(userId: student, programId: program.id!);
    expect((await h.db.getProgram(userId: student, programId: program.id!)).waitingSince, isNull);

    final context = await h.db.getCoachSendContext(coachId: coach, id: library, connectionId: connection);
    expect(context?.existingProgramId, program.id);
    expect(context?.studentBusy, isTrue);

    final holders = await h.db.getCoachProgramHolders(coachId: coach, id: library);
    expect(holders.single.studentId, student);
    expect(holders.single.version, 1);
    expect(await h.db.getCoachProgramHolders(coachId: student, id: library), isEmpty);
  });

  group('sending', () {
    Future<ProgramDelivery> send(String coach, String id, String connection) {
      final req = bareRequest()
        ..coachLibraryService = h.db
        ..programService = h.db;
      return deliverCoachProgram(req, coachId: coach, id: id, connectionId: connection);
    }

    Future<(String, Map<String, dynamic>)> library(String coach) async {
      final customExercise = await h.insertId(
        "INSERT INTO exercises (name, category, target, user_id) VALUES (@n, 'Barbell', 'Chest', @u) RETURNING id",
        {'n': 'Coach press ${h.uid('x')}', 'u': coach},
      );
      final id = uuidV7();
      final document = withRowIds({
        'name': 'Five three one',
        'note': 'For the coach to write',
        'rules': {
          customExercise: {'kind': 'addWeight', 'step': 2.5},
        },
        'sessions': [
          {
            'name': 'Monday',
            'exercises': [
              {
                'exercise': {'id': customExercise},
                'sets': [
                  {'weight': 100, 'reps': 5},
                ],
              },
            ],
          },
        ],
      });
      await h.db.saveCoachProgram(coachId: coach, id: id, name: 'Five three one', body: document);
      return (id, document);
    }

    test('two students each get their own copy, with the coach\'s custom exercise', () async {
      final (coach, one, connection) = await coaching();
      final two = await h.seedProfile();
      await h.exec(
        '''
        INSERT INTO connections (initiator_id, target_id, initiator_role, target_role, domain, status)
        VALUES (@c, @s, 'COACH', 'STUDENT', 'fitness', 'active')
        ''',
        {'c': coach, 's': two},
      );
      final second = (await h.db.getConnections(two)).single.connectionId!;
      final (id, document) = await library(coach);

      final first = await send(coach, id, connection);
      final next = await send(coach, id, second);
      expect(first.delivered, isTrue, reason: '${first.reason}');
      expect(next.delivered, isTrue, reason: 'no id_taken for the second: ${next.reason}');

      final read = await h.db.getProgram(userId: one, programId: first.programId!);
      final session = ((document['sessions'] as List).single as Map)['id'];
      expect(read.sessions, isNot(contains(session)));
      expect(read.coachId, coach);

      final exercises = await h.exec(
        '''
        SELECT e.user_id, e.id
        FROM template_exercises te
        JOIN exercises e ON e.id = te.exercise_id
        WHERE te.template_id = ANY(@sessions::uuid[])
        ''',
        {'sessions': read.sessions},
      );
      expect(exercises.single[0], one);
      expect(
        read.rules.keys.single,
        exercises.single[1].toString(),
        reason: 'the rule follows the student\'s exercise',
      );

      final assigned = await h.exec('SELECT assigned_by FROM templates WHERE id = ANY(@s::uuid[])', {
        's': read.sessions,
      });
      expect(assigned.single[0], coach);

      // cleared by hand: a seeded student's custom exercise holds up the cascade
      await h.exec('DELETE FROM templates WHERE user_id = ANY(@ids)', {
        'ids': [one, two, coach],
      });
    });

    test('sending what they hold answers that copy', () async {
      final (coach, student, connection) = await coaching();
      final (id, _) = await library(coach);
      final first = await send(coach, id, connection);
      final again = await send(coach, id, connection);
      expect(again.programId, first.programId);
      await h.exec('DELETE FROM templates WHERE user_id = @s', {'s': student});
    });

    test('a student at their limit is told as not delivered, not an error', () async {
      final (coach, student, connection) = await coaching();
      final (id, _) = await library(coach);
      await h.exec(
        '''
        INSERT INTO programs (user_id, name)
        SELECT @s, 'p' || g FROM generate_series(1, 100) g
        ''',
        {'s': student},
      );
      final delivery = await send(coach, id, connection);
      expect(delivery.delivered, isFalse);
      expect(delivery.reason, 'program_limit');
    });

    test('a client this coach doesn\'t coach comes back as not delivered', () async {
      final (coach, _, _) = await coaching();
      final (_, _, theirs) = await coaching();
      final (id, _) = await library(coach);
      final delivery = await send(coach, id, theirs);
      expect(delivery.delivered, isFalse);
      expect(delivery.reason, 'not_coaching');
    });

    test('a session the coach filed arrives unfiled, not as a missing folder', () async {
      final (coach, student, connection) = await coaching();
      final folder = await h.insertId(
        "INSERT INTO template_folders (user_id, name) VALUES (@c, 'Mine') RETURNING id",
        {'c': coach},
      );
      final id = uuidV7();
      await h.db.saveCoachProgram(
        coachId: coach,
        id: id,
        name: 'Filed',
        body: withRowIds({
          'name': 'Filed',
          'sessions': [
            {'name': 'Monday', 'folderId': folder, 'exercises': <Object?>[]},
          ],
        }),
      );
      final delivery = await send(coach, id, connection);
      expect(delivery.delivered, isTrue, reason: '${delivery.reason}');
      final read = await h.db.getProgram(userId: student, programId: delivery.programId!);
      expect((await h.db.getTemplate(userId: student, templateId: read.sessions.single)).folder, isNull);
    });

    test('sessions with no order keep the order they are written in', () async {
      final (coach, student, connection) = await coaching();
      final id = uuidV7();
      final days = [for (var i = 0; i < 12; i++) 'Day $i'];
      await h.db.saveCoachProgram(
        coachId: coach,
        id: id,
        name: 'Many',
        body: withRowIds({
          'name': 'Many',
          'sessions': [
            for (final day in days) {'name': day, 'exercises': <Object?>[]},
          ],
        }),
      );
      final delivery = await send(coach, id, connection);
      final read = await h.db.getProgram(userId: student, programId: delivery.programId!);
      final names = [
        for (final session in read.sessions) (await h.db.getTemplate(userId: student, templateId: session)).name,
      ];
      expect(names, days);
    });

    test('an exercise the coach no longer has comes back as not delivered, not dropped', () async {
      final (coach, student, connection) = await coaching();
      final (id, document) = await library(coach);
      final exercise = idsIn(document['rules']).single;
      await h.exec('DELETE FROM exercises WHERE id = @e::uuid', {'e': exercise});
      final delivery = await send(coach, id, connection);
      expect(delivery.delivered, isFalse);
      expect(delivery.reason, 'unknown_exercise');
      expect(await h.db.getPrograms(student), isEmpty);
    });

    test('a student whose library is full is told as not delivered, not an error', () async {
      final (coach, student, connection) = await coaching();
      final (id, _) = await library(coach);
      await h.exec(
        '''
        INSERT INTO exercises (name, category, target, user_id)
        SELECT 'Mine ' || g, 'Barbell', 'Chest', @s FROM generate_series(1, 2000) g
        ''',
        {'s': student},
      );
      final delivery = await send(coach, id, connection);
      expect(delivery.delivered, isFalse);
      expect(delivery.reason, 'bad_request');
    });

    test('a second copy racing the first answers as already sent', () async {
      final (coach, student, connection) = await coaching();
      final library = uuidV7();
      await h.db.saveCoachProgram(coachId: coach, id: library, name: 'One', body: body('One'));
      Future<void> copy() => h.db.createProgramOrExisting(
        userId: student,
        program: Program(name: 'One'),
        sessions: const [],
        copy: (
          coachId: coach,
          connectionId: connection,
          libraryProgramId: library,
          libraryVersion: 1,
          libraryIds: const {},
          waits: false,
        ),
      );
      await copy();
      await expectLater(copy(), throwsA(isA<Conflict>()));
    });
  });

  group('who holds a program', () {
    test('only those the coach still coaches', () async {
      final (coach, student, connection) = await coaching();
      final library = uuidV7();
      await h.db.saveCoachProgram(coachId: coach, id: library, name: 'One', body: body('One'));
      final req = bareRequest()
        ..coachLibraryService = h.db
        ..programService = h.db;
      await deliverCoachProgram(req, coachId: coach, id: library, connectionId: connection);
      expect(await h.db.getCoachProgramHolders(coachId: coach, id: library), hasLength(1));

      await h.exec('INSERT INTO blocks (blocker_id, blocked_id) VALUES (@s, @c)', {'s': student, 'c': coach});
      expect(await h.db.getCoachProgramHolders(coachId: coach, id: library), isEmpty);
    });
  });

  test('an invitation names a program only of its coach\'s', () async {
    final (coach, other) = (await h.seedProfile(), await h.seedProfile());
    await h.exec("INSERT INTO entitlements (user_id, entitlement) VALUES (@u, 'coach')", {'u': coach});
    final invitation = await h.db.createInvitation(inviterId: coach, name: 'Alex', domain: .fitness, token: h.uid('t'));
    final mine = uuidV7();
    final theirs = uuidV7();
    await h.db.saveCoachProgram(coachId: coach, id: mine, name: 'One', body: body('One'));
    await h.db.saveCoachProgram(coachId: other, id: theirs, name: 'One', body: body('One'));

    await expectLater(
      h.db.attachInvitationProgram(coachId: coach, invitationId: invitation.id, programId: theirs),
      throwsA(anything),
    );
    await h.db.attachInvitationProgram(coachId: coach, invitationId: invitation.id, programId: mine);
    expect(await h.db.invitationProgram(token: invitation.token!), mine);
  });
}

class _Harness extends DatabaseTestBase;
