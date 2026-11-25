@Tags(['db'])
library;

import 'package:heart/globals/globals.dart';
import 'package:heart/inputs/inputs.dart';
import 'package:heart/middleware/database.dart';
import 'package:heart/routes/roster.dart';
import 'package:heart_models/heart_models.dart';
import 'package:test/test.dart';

import '../helpers/request.dart';
import 'db_test_utility.dart';

void main() {
  final h = _Harness();

  setUpAll(h.setupDatabase);
  tearDownAll(h.teardownDatabase);

  Future<(String, String, String)> client({String? coach, DateTime? acceptedAt}) async {
    final (c, student) = (coach ?? await h.seedProfile(), await h.seedProfile());
    final rows = await h.exec(
      '''
      INSERT INTO connections (initiator_id, target_id, initiator_role, target_role, domain, status, accepted_at)
      VALUES (@c, @s, 'COACH', 'STUDENT', 'fitness', 'active', @at::timestamptz)
      RETURNING id
      ''',
      {'c': c, 's': student, 'at': (acceptedAt ?? DateTime.utc(2020)).toIso8601String()},
    );
    return (c, student, rows.first[0].toString());
  }

  Future<Page<ClientSummary>> roster(
    String coach, {
    String? reason,
    bool former = false,
    String? cursor,
    int limit = 50,
  }) async {
    // the route's first page works out what changed
    final req = bareRequest(method: .get)
      ..user = User(id: coach)
      ..rosterService = h.db
      ..programChangeService = h.db
      ..programService = h.db;
    await getRoster(req);
    return h.db.getRoster(
      coachId: coach,
      reason: reason,
      former: former,
      cursor: OrderedCursor.tryParse(cursor),
      limit: limit,
    );
  }

  Future<String> trained(String student, {DateTime? at, String? note}) {
    final start = at ?? DateTime.now().toUtc().subtract(const Duration(hours: 1));
    return h.insertId(
      'INSERT INTO workouts (user_id, name, started_at, completed_at, note) VALUES (@u, @n, @s, @s, @note) RETURNING id',
      {'u': student, 'n': 'Trained', 's': start, 'note': note},
    );
  }

  test('a summary says what the coach can see', () async {
    final (coach, student, _) = await client();
    final at = DateTime.now().toUtc().subtract(const Duration(days: 2));
    await trained(student, at: at);

    final summary = (await roster(coach)).items.single;
    expect(summary.studentId, student);
    expect(summary.status, 'active');
    expect(summary.recent, hasLength(1));
    expect(summary.lastTrainedAt?.difference(at).inSeconds.abs(), lessThan(2));
    expect(summary.reasons, isEmpty);
    expect(summary.toMap().containsKey('email'), isFalse);
  });

  group('a reason', () {
    test('a note, until the coach has looked', () async {
      final (coach, student, connection) = await client();
      await trained(student, note: 'knees felt fine');
      expect((await roster(coach)).items.single.reasons, ['note']);

      await h.db.markReviewed(coachId: coach, connectionId: connection);
      expect((await roster(coach)).items.single.reasons, isEmpty);

      await trained(student, at: DateTime.now().toUtc().add(const Duration(minutes: 5)), note: 'and again');
      expect((await roster(coach)).items.single.reasons, ['note']);
    });

    test('a note on a workout that arrives after the coach looked, however early it started', () async {
      final (coach, student, connection) = await client();
      await roster(coach);
      await h.db.markReviewed(coachId: coach, connectionId: connection);

      await trained(student, at: DateTime.now().toUtc().subtract(const Duration(days: 3)), note: 'synced late');
      expect((await roster(coach)).items.single.reasons, ['note']);
    });

    test('not a note the coach wrote on a workout they logged', () async {
      final (coach, student, _) = await client();
      await h.exec(
        '''
        INSERT INTO workouts (user_id, name, started_at, completed_at, note, logged_by)
        VALUES (@s, 'In person', now() - INTERVAL '1 hour', now(), 'good session', @c)
        ''',
        {'s': student, 'c': coach},
      );
      final summary = (await roster(coach)).items.single;
      expect(summary.reasons, isEmpty);
      expect(summary.recent, hasLength(1), reason: 'it is still the client\'s training');
    });

    test('a late look doesn\'t bring back what a later one cleared', () async {
      final (coach, student, connection) = await client();
      await trained(student, note: 'knees felt fine');
      await h.db.markReviewed(coachId: coach, connectionId: connection);
      await h.db.markReviewed(
        coachId: coach,
        connectionId: connection,
        at: DateTime.now().toUtc().subtract(const Duration(days: 1)),
      );
      expect((await roster(coach)).items.single.reasons, isEmpty);
    });

    test('nobody is a gap for a week after resuming', () async {
      final (coach, student, connection) = await client();
      await trained(student, at: DateTime.now().toUtc().subtract(const Duration(days: 10)));
      expect((await roster(coach)).items.single.reasons, ['gap']);

      for (final status in ['paused', 'active']) {
        await h.exec('UPDATE connections SET status = @status, status_by = @s WHERE id = @c::uuid', {
          'status': status,
          's': student,
          'c': connection,
        });
      }
      expect((await roster(coach)).items.single.reasons, isEmpty);
    });

    test('a gap, which clears when they train', () async {
      final (coach, student, _) = await client();
      await trained(student, at: DateTime.now().toUtc().subtract(const Duration(days: 8)));
      expect((await roster(coach)).items.single.reasons, ['gap']);
      await trained(student);
      expect((await roster(coach)).items.single.reasons, isEmpty);
    });

    test('nobody is a gap for a week after accepting', () async {
      final (coach, _, _) = await client(acceptedAt: DateTime.now().toUtc());
      expect((await roster(coach)).items.single.reasons, isEmpty);
    });

    test('lighter than planned, and following a lighter week is not', () async {
      final (coach, student, _) = await client();
      final exercise = await h.seedGlobalExercise();
      final workout = await trained(student);
      final we = await h.insertId(
        'INSERT INTO workout_exercises (workout_id, exercise_id, exercise_order) VALUES (@w::uuid, @e::uuid, 0) RETURNING id',
        {'w': workout, 'e': exercise},
      );
      final set = await h.insertId(
        '''
        INSERT INTO exercise_sets (workout_exercise_id, weight, reps, completed, set_order)
        VALUES (@we::uuid, 50, 5, true, 0)
        RETURNING id
        ''',
        {'we': we},
      );
      await h.db.savePlan(
        userId: student,
        workoutId: workout,
        plan: {
          'exercises': [
            {
              'sets': [
                {'weight': 50, 'setId': set},
              ],
            },
          ],
        },
      );
      expect((await roster(coach)).items.single.reasons, isEmpty);

      await h.exec('UPDATE exercise_sets SET weight = 40 WHERE id = @s::uuid', {'s': set});
      await h.exec('UPDATE workouts SET note = NULL WHERE id = @w::uuid', {'w': workout});
      expect((await roster(coach)).items.single.reasons, ['lighter']);
    });
  });

  test('a plan of the wrong shape, however it got there, takes nothing down', () async {
    final (coach, student, _) = await client();
    final workout = await trained(student);
    await h.exec(
      '''INSERT INTO workout_plans (workout_id, plan) VALUES (@w::uuid, '{"exercises": {"x": 1}}')''',
      {'w': workout},
    );
    final summary = (await roster(coach)).items.single;
    expect(summary.reasons, isEmpty);
    expect(summary.recent, hasLength(1));
  });

  test('working one out over a change still being written leaves it dirty', () async {
    final (coach, student, _) = await client();
    final read = (await h.db.getDirtySummaries(coachId: coach)).single;

    await trained(student);
    await h.db.refreshSummary(
      connectionId: read.connectionId,
      coachId: read.coachId,
      studentId: read.studentId,
      generation: read.generation,
      ending: false,
    );
    expect(await h.db.getDirtySummaries(coachId: coach), hasLength(1), reason: 'it read from before the workout');

    final again = (await h.db.getDirtySummaries(coachId: coach)).single;
    await h.db.refreshSummary(
      connectionId: again.connectionId,
      coachId: again.coachId,
      studentId: again.studentId,
      generation: again.generation,
      ending: false,
    );
    expect(await h.db.getDirtySummaries(coachId: coach), isEmpty);
  });

  test('recent times age out, whether or not anything marked the summary', () async {
    final (coach, student, connection) = await client();
    await trained(student);
    await roster(coach);
    await h.exec(
      '''
      UPDATE client_summaries
      SET recent = ARRAY[now() - INTERVAL '20 days', now() - INTERVAL '1 day'], dirty = false
      WHERE connection_id = @c::uuid
      ''',
      {'c': connection},
    );
    expect((await roster(coach)).items.single.recent, hasLength(1));
  });

  test('every client changed since the coach looked is worked out, however many', () async {
    final coach = await h.seedProfile();
    final prefix = h.uid('many');
    await h.exec(
      '''
      WITH _students AS (
        INSERT INTO profiles (id, username, email)
        SELECT @p || n, 'u_' || @p || n, @p || n || '@test.local'
        FROM generate_series(1, 201) n
        RETURNING id
      )
      INSERT INTO connections (initiator_id, target_id, initiator_role, target_role, domain, status, accepted_at)
      SELECT @c, id, 'COACH', 'STUDENT', 'fitness', 'active', '2020-01-01Z'
      FROM _students
      ''',
      {'p': prefix, 'c': coach},
    );
    try {
      expect(await h.db.getDirtySummaries(coachId: coach), hasLength(201));
    } finally {
      await h.exec("DELETE FROM profiles WHERE id LIKE @p || '%'", {'p': prefix});
    }
  });

  group('on a program', () {
    Future<String> program(String coach, String student, String connection) async {
      final id = await h.insertId(
        '''
        INSERT INTO programs (user_id, name, weeks, coach_id, connection_id)
        VALUES (@s, 'Block', 1, @c, @connection::uuid)
        RETURNING id
        ''',
        {'s': student, 'c': coach, 'connection': connection},
      );
      await h.exec(
        '''
        INSERT INTO templates (user_id, name, program_id, joined_program_at, assigned_by)
        VALUES (@s, 'Day', @p::uuid, '2020-01-01Z', @c)
        ''',
        {'s': student, 'p': id, 'c': coach},
      );
      return id;
    }

    test('it is ending in its last week, from a date that stays put, and not once finished', () async {
      final (coach, student, connection) = await client();
      final id = await program(coach, student, connection);

      final summary = (await roster(coach)).items.single;
      expect((summary.programId, summary.programWeek, summary.programWeeks), (id, 1, 1));
      expect(summary.reasons, contains('ending'));
      final ending = (await h.db.getCoachFeed(coachId: coach)).items.single;
      expect((ending.kind, ending.id), ('ending', id));

      await h.exec('UPDATE client_summaries SET dirty = true WHERE connection_id = @c::uuid', {'c': connection});
      await roster(coach);
      expect((await h.db.getCoachFeed(coachId: coach)).items.single.at, ending.at, reason: 'working it out again');

      final session = (await h.exec('SELECT id::text FROM templates WHERE program_id = @p::uuid', {'p': id})).single[0];
      await h.exec(
        '''
        INSERT INTO workouts (user_id, name, started_at, completed_at, template_id, program_id)
        VALUES (@s, 'Day', now() - INTERVAL '1 hour', now(), @t::uuid, @p::uuid)
        ''',
        {'s': student, 't': session, 'p': id},
      );
      final finished = (await roster(coach)).items.single;
      expect(finished.programWeek, 2);
      expect(finished.reasons, isNot(contains('ending')));
      expect((await h.db.getCoachFeed(coachId: coach)).items.map((each) => each.kind), ['workout']);
    });

    Future<void> changes(String actor, String student, String program, String name) async {
      final written = await h.db.writeProgramFields(
        ownerId: student,
        actorId: actor,
        programId: program,
        program: Program(name: name, weeks: 1),
      );
      expect(written?.name, name);
    }

    test('the client changed it, until the coach has looked', () async {
      final (coach, student, connection) = await client();
      final id = await program(coach, student, connection);
      expect((await roster(coach)).items.single.reasons, isNot(contains('changed')));

      expect((await roster(coach)).items.single.changedPrograms, isEmpty);

      await changes(student, student, id, 'Block, my way');
      expect((await roster(coach)).items.single.reasons, contains('changed'));
      expect((await roster(coach, reason: 'changed')).items.single.studentId, student);
      final at =
          (await h.exec(
                'SELECT max(at) FROM program_changes WHERE program_id = @p::uuid AND actor_id = @s',
                {'p': id, 's': student},
              )).single[0]!
              as DateTime;
      expect((await roster(coach)).items.single.changedPrograms, [ChangedProgram(id, at)]);

      await h.db.markReviewed(coachId: coach, connectionId: connection);
      expect((await roster(coach)).items.single.reasons, isNot(contains('changed')));
      expect((await roster(coach)).items.single.changedPrograms, isEmpty);

      await changes(student, student, id, 'Block, my way again');
      expect((await roster(coach)).items.single.reasons, contains('changed'));
      expect((await roster(coach)).items.single.changedPrograms.single.changedAt.isAfter(at), isTrue);
    });

    test('says which copies changed since the coach looked, each by its latest change, newest first', () async {
      final (coach, student, connection) = await client();
      final (first, second, untouched) = (
        await program(coach, student, connection),
        await program(coach, student, connection),
        await program(coach, student, connection),
      );
      Future<void> at(String program, String name, String when) async {
        await changes(student, student, program, name);
        await h.exec(
          'UPDATE program_changes SET at = @when::timestamptz WHERE program_id = @p::uuid AND actor_id = @s AND at > @when::timestamptz',
          {'p': program, 's': student, 'when': when},
        );
        await h.exec('UPDATE client_summaries SET dirty = true WHERE connection_id = @c::uuid', {'c': connection});
      }

      await at(first, 'First, older', '2026-01-01Z');
      await at(second, 'Second', '2026-01-02Z');
      await h.db.markReviewed(coachId: coach, connectionId: connection, at: DateTime.utc(2026, 1, 1, 12));
      await at(first, 'First, newer', '2026-01-03Z');
      expect((await roster(coach)).items.single.changedPrograms, [
        ChangedProgram(first, DateTime.utc(2026, 1, 3)),
        ChangedProgram(second, DateTime.utc(2026, 1, 2)),
      ]);
      expect(
        (await roster(coach)).items.single.changedPrograms.map((each) => each.programId),
        isNot(contains(untouched)),
      );
    });

    test('a session the client changed is the program changed', () async {
      final (coach, student, connection) = await client();
      final id = await program(coach, student, connection);
      await roster(coach);

      final session = (await h.exec('SELECT id::text FROM templates WHERE program_id = @p::uuid', {'p': id})).single[0];
      await h.db.removeSession(ownerId: student, actorId: student, sessionId: session! as String);
      expect((await roster(coach)).items.single.reasons, contains('changed'));
    });

    test('the coach changing it is no reason, before or after the client\'s own', () async {
      final (coach, student, connection) = await client();
      final id = await program(coach, student, connection);
      await changes(coach, student, id, 'Block, from the coach');
      expect((await roster(coach)).items.single.reasons, isNot(contains('changed')));

      await changes(student, student, id, 'Block, my way');
      await roster(coach);
      await h.db.markReviewed(coachId: coach, connectionId: connection);
      await changes(coach, student, id, 'Block, from the coach again');
      expect((await roster(coach)).items.single.reasons, isNot(contains('changed')));
    });

    test('a session the client added is the program changed, though no history says so', () async {
      final (coach, student, connection) = await client();
      final id = await program(coach, student, connection);
      await roster(coach);
      await h.exec("INSERT INTO templates (user_id, name, program_id) VALUES (@s, 'Mine', @p::uuid)", {
        's': student,
        'p': id,
      });
      expect((await roster(coach)).items.single.reasons, contains('changed'));
      expect((await roster(coach)).items.single.changedPrograms.single.programId, id);

      await h.db.markReviewed(coachId: coach, connectionId: connection);
      expect((await roster(coach)).items.single.reasons, isNot(contains('changed')));
    });

    test('archiving a program is not changing it', () async {
      final (coach, student, connection) = await client();
      final id = await program(coach, student, connection);
      await h.db.writeProgramFields(
        ownerId: student,
        actorId: student,
        programId: id,
        program: Program(name: 'Block', weeks: 1, archived: true),
      );
      expect((await h.exec('SELECT 1 FROM program_changes WHERE program_id = @p::uuid', {'p': id})), hasLength(1));
      expect((await roster(coach)).items.single.reasons, isNot(contains('changed')));
    });

    test('a ladder\'s step up is not the client changing it, and swapping another exercise is', () async {
      final (coach, student, connection) = await client();
      final id = await program(coach, student, connection);
      final session = (await h.exec('SELECT id::text FROM templates WHERE program_id = @p::uuid', {'p': id})).single[0];
      final (goblet, front, other) = (
        await h.seedGlobalExercise(),
        await h.seedGlobalExercise(),
        await h.seedGlobalExercise(),
      );
      Future<void> holds(String actor, String exercise) async {
        await h.db.writeSession(
          ownerId: student,
          actorId: actor,
          sessionId: session! as String,
          body: TemplateUpdateIn.fromJson({
            'name': 'Day',
            'exercises': [
              {
                'exercise': exercise,
                'order': 0,
                'sets': [
                  {'reps': 5},
                ],
              },
            ],
          }, userId: student).request,
        );
      }

      await holds(coach, goblet);
      await h.exec(
        '''
        INSERT INTO program_actions (user_id, program_id, kind, at, from_exercise, to_exercise)
        VALUES (@s, @p::uuid, 'advance', now(), @f::uuid, @t::uuid)
        ''',
        {'s': student, 'p': id, 'f': goblet, 't': front},
      );
      await holds(student, front);
      expect(await h.exec('SELECT 1 FROM program_changes WHERE actor_id = @s', {'s': student}), hasLength(1));
      expect((await roster(coach)).items.single.reasons, isNot(contains('changed')));

      await holds(student, other);
      expect((await roster(coach)).items.single.reasons, contains('changed'));
    });

    test('a change made during a pause is none the coach can read', () async {
      final (coach, student, connection) = await client();
      final id = await program(coach, student, connection);
      Future<void> status(String status) => h.exec(
        'UPDATE connections SET status = @status, status_by = @s WHERE id = @c::uuid',
        {'status': status, 's': student, 'c': connection},
      );
      await status('paused');
      await changes(student, student, id, 'Block, while paused');
      await status('active');
      expect((await roster(coach)).items.single.reasons, isNot(contains('changed')));
    });

    test('a program another coach sent is none of this one\'s', () async {
      final (coach, student, _) = await client();
      final (other, _, _) = await client();
      final theirs = await h.insertId(
        '''
        INSERT INTO connections (initiator_id, target_id, initiator_role, target_role, domain, status, accepted_at)
        VALUES (@c, @s, 'COACH', 'STUDENT', 'fitness', 'active', '2020-01-01Z')
        RETURNING id
        ''',
        {'c': other, 's': student},
      );
      await changes(student, student, await program(other, student, theirs), 'Theirs, my way');

      expect((await roster(coach)).items.single.reasons, isNot(contains('changed')));
      final seen = (await roster(other)).items.singleWhere((each) => each.studentId == student);
      expect(seen.reasons, contains('changed'));
    });
  });

  group('what it can\'t see', () {
    test('a hidden workout moves nothing, and hiding one puts it back', () async {
      final (coach, student, _) = await client();
      final old = DateTime.now().toUtc().subtract(const Duration(days: 8));
      await trained(student, at: old);
      final hidden = await trained(student, note: 'a hidden note');

      expect((await roster(coach)).items.single.reasons, ['note']);

      await h.db.hideWorkout(userId: student, workoutId: hidden);
      final summary = (await roster(coach)).items.single;
      expect(summary.reasons, ['gap']);
      expect(summary.recent, hasLength(1));

      await h.db.unhideWorkout(userId: student, workoutId: hidden);
      expect((await roster(coach)).items.single.reasons, ['note']);
    });

    test('a workout before they connected is not counted', () async {
      final (coach, student, _) = await client(acceptedAt: DateTime.now().toUtc());
      await trained(student, at: DateTime.utc(2021), note: 'long ago');
      final summary = (await roster(coach)).items.single;
      expect(summary.lastTrainedAt, isNull);
      expect(summary.reasons, isEmpty);
    });
  });

  group('the list', () {
    test('those who need a word first, filtered by reason, paged', () async {
      final coach = await h.seedProfile();
      final fine = <String>[];
      for (var i = 0; i < 3; i++) {
        final (_, student, _) = await client(coach: coach);
        await trained(student);
        fine.add(student);
      }
      final (_, needy, _) = await client(coach: coach);
      await trained(needy, note: 'hello');

      final first = await roster(coach, limit: 2);
      expect(first.items.first.studentId, needy);
      expect(first.hasMore, isTrue);

      final last = first.items.last;
      final next = await roster(coach, limit: 2, cursor: '${last.reasons.isEmpty ? 1 : 0}:${last.connectionId}');
      expect(next.items, hasLength(2));
      expect({...first.items, ...next.items}.map((each) => each.studentId).toSet(), {...fine, needy});

      expect((await roster(coach, reason: 'note')).items.single.studentId, needy);
      expect(await roster(coach, reason: 'gap').then((page) => page.items), isEmpty);
    });

    test('someone else\'s clients are not there, and nor is the student\'s own side', () async {
      final (coach, student, connection) = await client();
      final other = await h.seedProfile();
      expect((await roster(other)).items, isEmpty);
      expect((await roster(student)).items, isEmpty);

      expect(await h.db.markReviewed(coachId: other, connectionId: connection), isFalse);
      final reviewed = await h.exec('SELECT reviewed_at FROM client_summaries WHERE connection_id = @c::uuid', {
        'c': connection,
      });
      expect(reviewed.first[0], isNull);
      expect((await roster(coach)).items, hasLength(1));
    });

    test('a former client is on a list of their own, as who and when', () async {
      final (coach, student, _) = await client();
      await trained(student, note: 'a note');
      await roster(coach);
      await h.db.deleteConnection(actorId: student, targetId: coach, role: .student, domain: .fitness);

      expect((await roster(coach)).items, isEmpty);
      final former = (await roster(coach, former: true)).items.single;
      expect(former.status, 'severed');
      expect(former.acceptedAt, isNotNull);
      expect(former.lastTrainedAt, isNull);
      expect(former.recent, isEmpty);
      expect(former.reasons, isEmpty);
      expect(
        (await roster(coach, former: true, reason: 'gap')).items,
        hasLength(1),
        reason: 'a reason filters nothing',
      );
    });

    test('someone who blocked the coach is no former client', () async {
      final (coach, student, connection) = await client();
      await roster(coach);
      await h.exec("UPDATE connections SET status = 'blocked', status_by = @s WHERE id = @c::uuid", {
        's': student,
        'c': connection,
      });
      expect((await roster(coach, former: true)).items, isEmpty);

      await h.exec('UPDATE blocks SET lifted_at = now() WHERE blocker_id = @s', {'s': student});
      expect((await roster(coach, former: true)).items.single.status, 'severed');
    });
  });

  group('the feed', () {
    test('finished workouts and skips, newest first, without what it can\'t see', () async {
      final (coach, student, _) = await client();
      final older = await trained(student, at: DateTime.now().toUtc().subtract(const Duration(days: 3)));
      final hidden = await trained(student, at: DateTime.now().toUtc().subtract(const Duration(days: 2)));
      await h.db.hideWorkout(userId: student, workoutId: hidden);
      await h.db.createSkip(
        userId: student,
        skip: TrainingSkip(id: uuidV7(), at: DateTime.now().toUtc().subtract(const Duration(days: 1)), reason: 'sick'),
      );

      final items = (await h.db.getCoachFeed(coachId: coach)).items;
      expect(items.map((each) => each.kind), ['skip', 'workout']);
      expect(items.last.id, older);
      expect(items.first.toMap().toString(), isNot(contains('sick')));
    });

    test('pages', () async {
      final (coach, student, _) = await client();
      for (var i = 1; i <= 3; i++) {
        await trained(student, at: DateTime.now().toUtc().subtract(Duration(days: i)));
      }
      final first = await h.db.getCoachFeed(coachId: coach, limit: 2);
      expect(first.items, hasLength(2));
      expect(first.hasMore, isTrue);
      final last = first.items.last;
      final next = await h.db.getCoachFeed(coachId: coach, limit: 2, cursor: (at: last.at, id: last.id));
      expect(next.items, hasLength(1));
    });

    test('a client coached in two domains is there once', () async {
      final (coach, student, _) = await client();
      await h.exec(
        '''
        INSERT INTO connections (initiator_id, target_id, initiator_role, target_role, domain, status, accepted_at)
        VALUES (@c, @s, 'COACH', 'STUDENT', 'running', 'active', '2020-01-01Z')
        ''',
        {'c': coach, 's': student},
      );
      await trained(student);
      expect((await h.db.getCoachFeed(coachId: coach)).items, hasLength(1));
    });

    test('a former client\'s drop out, and so does someone else\'s', () async {
      final (coach, student, _) = await client();
      await trained(student);
      await h.db.deleteConnection(actorId: coach, targetId: student, role: .coach, domain: .fitness);
      expect((await h.db.getCoachFeed(coachId: coach)).items, isEmpty);
    });
  });

  test('a finished workout owes the coach one daily push, however many', () async {
    final (coach, student, _) = await client();
    await trained(student);
    await trained(student);
    final owed = await h.exec('SELECT topic FROM push_digests WHERE user_id = @c', {'c': coach});
    expect(owed.single[0], 'coaching.workout_digest');
  });
}

class _Harness extends DatabaseTestBase;
