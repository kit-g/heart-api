@Tags(['db'])
library;

import 'package:heart/models/workouts.dart';
import 'package:heart_models/heart_models.dart';
import 'package:postgres/postgres.dart' show Sql;
import 'package:test/test.dart';

import 'db_test_utility.dart';

/// A workout's template and program (heart-api#215): stored when the caller
/// owns them, kept when a body leaves them out, and let go when what they name
/// is deleted. Tagged `db`.
void main() {
  final h = _Harness();

  late String userId;
  late String strangerId;

  String imageUrl(String key) => key;

  WorkoutRequest body(Map<String, dynamic> links) {
    return WorkoutRequest(
      userId: userId,
      body: {
        'name': 'Session A',
        'start': DateTime.utc(2026, 10, 14, 18).toIso8601String(),
        'end': DateTime.utc(2026, 10, 14, 19).toIso8601String(),
        ...links,
      },
    );
  }

  /// A program with one session, returning both ids.
  Future<(String program, String template)> seedProgram(String owner) async {
    final (program, _) = await h.db.createProgramOrExisting(
      userId: owner,
      program: Program(name: 'Getting stronger'),
      sessions: [TemplateRequest(userId: owner, name: 'A')],
    );
    return (program.id!, program.sessions.single);
  }

  setUpAll(() async {
    await h.setupDatabase();
    userId = await h.seedProfile();
    strangerId = await h.seedProfile();
  });

  tearDownAll(h.teardownDatabase);

  test('a workout started from a session names it and its program', () async {
    final (program, template) = await seedProgram(userId);

    final (workout, _) = await h.db.createWorkout(
      userId: userId,
      body: body({'templateId': template, 'programId': program}),
      imageUrl: imageUrl,
    );

    expect(workout.templateId, template);
    expect(workout.programId, program);
    final read = await h.db.getWorkout(userId: userId, workoutId: workout.id, imageUrl: imageUrl);
    expect((read.templateId, read.programId), (template, program));
  });

  test("someone else's template or program, or no id at all, saves the workout unlinked", () async {
    final (program, template) = await seedProgram(strangerId);

    final (theirs, _) = await h.db.createWorkout(
      userId: userId,
      body: body({'templateId': template, 'programId': program}),
      imageUrl: imageUrl,
    );
    expect(theirs.templateId, isNull);
    expect(theirs.programId, isNull);

    final (garbage, _) = await h.db.createWorkout(
      userId: userId,
      body: body({'templateId': '1700000000000', 'programId': 42}),
      imageUrl: imageUrl,
    );
    expect(garbage.templateId, isNull);
  });

  group('a template the server holds nothing for (heart-api#474)', () {
    // a sample's id is the content's own, and no v7
    const sample = '3b790e9f-98da-44f6-bb5d-53044635da6c';

    Future<String?> read(String workout) async {
      return (await h.db.getWorkout(userId: userId, workoutId: workout, imageUrl: imageUrl)).templateId;
    }

    Future<Workout> save(Map<String, dynamic> links) async {
      final (workout, _) = await h.db.createWorkout(userId: userId, body: body(links), imageUrl: imageUrl);
      return workout;
    }

    Future<String> template({String? id}) async {
      final (stored, _) = await h.db.createTemplateOrExisting(
        userId: userId,
        body: TemplateRequest(userId: userId, id: id, name: 'A'),
      );
      return stored.id;
    }

    test('a sample is named by every read of its owner\'s', () async {
      final workout = await save({'templateId': sample});
      expect(workout.templateId, sample);
      expect(await read(workout.id), sample);

      final listed = await h.db.getWorkouts(
        userId: userId,
        targetUserId: userId,
        imageUrl: imageUrl,
      );
      expect(listed.items.singleWhere((each) => each.id == workout.id).templateId, sample);

      final patched = await h.db.patchWorkout(
        userId: userId,
        workoutId: workout.id,
        name: 'Renamed',
        imageUrl: imageUrl,
      );
      expect(patched.templateId, sample);

      final kept = await h.db.updateWorkout(userId: userId, workoutId: workout.id, body: body({}), imageUrl: imageUrl);
      expect(kept.templateId, sample);
      final cleared = await h.db.updateWorkout(
        userId: userId,
        workoutId: workout.id,
        body: body({'templateId': null}),
        imageUrl: imageUrl,
      );
      expect(cleared.templateId, isNull);
      final again = await h.db.updateWorkout(
        userId: userId,
        workoutId: workout.id,
        body: body({'templateId': sample}),
        imageUrl: imageUrl,
      );
      expect(again.templateId, sample);
    });

    test('someone else reading the workout isn\'t given it', () async {
      final coach = await h.seedProfile();
      await h.exec(
        '''
        INSERT INTO connections (initiator_id, target_id, initiator_role, target_role, domain, status, accepted_at)
        VALUES (@c, @s, 'COACH', 'STUDENT', 'fitness', 'active', '2020-01-01Z')
        ''',
        {'c': coach, 's': userId},
      );
      final workout = await save({'templateId': sample});
      final seen = await h.db.getWorkouts(userId: coach, targetUserId: userId, imageUrl: imageUrl);
      expect(seen.items.singleWhere((each) => each.id == workout.id).templateId, isNull);
    });

    test(
      'a save repeated, the owner\'s own read by id and the change feed name it, and a coach\'s read doesn\'t',
      () async {
        final coach = await h.seedProfile();
        final owner = await h.seedProfile();
        await h.exec(
          '''
        INSERT INTO connections (initiator_id, target_id, initiator_role, target_role, domain, status, accepted_at)
        VALUES (@c, @s, 'COACH', 'STUDENT', 'fitness', 'active', '2020-01-01Z')
        ''',
          {'c': coach, 's': owner},
        );
        final id = uuidV7();
        final request = WorkoutRequest(
          userId: owner,
          body: {
            'id': id,
            'name': 'Session A',
            'start': DateTime.utc(2026, 10, 14, 18).toIso8601String(),
            'end': DateTime.utc(2026, 10, 14, 19).toIso8601String(),
            'templateId': sample,
          },
        );
        Future<(Workout, bool)> again() => h.db.createWorkout(userId: owner, body: request, imageUrl: imageUrl);
        await again();
        final (repeated, created) = await again();
        expect((repeated.templateId, created), (sample, false));

        Future<String?> seenBy(String reader) async {
          final workout = await h.db.getTargetWorkout(
            requesterId: reader,
            targetUserId: owner,
            workoutId: id,
            imageUrl: imageUrl,
          );
          return workout.templateId;
        }

        expect(await seenBy(owner), sample);
        expect(await seenBy(coach), isNull);

        // the feed stops short of any transaction still running, which other suites keep
        for (var i = 0; ; i++) {
          final feed = await h.db.getWorkoutChanges(userId: owner, limit: 10, imageUrl: imageUrl);
          if (feed.upserted.isEmpty && i < 50) {
            await Future<void>.delayed(const Duration(milliseconds: 100));
            continue;
          }
          expect(feed.upserted.single.templateId, sample);
          break;
        }
      },
    );

    test('deleted before it ever arrived, it is named no more, and not by a workout still to come', () async {
      final id = uuidV7();
      final workout = await save({'templateId': id});
      await h.db.deleteTemplate(coachId: userId, templateId: id);
      expect(await read(workout.id), isNull);
      expect((await save({'templateId': id})).templateId, isNull);
    });

    test('a workout and its template written at once end up linked, whichever is first', () async {
      Future<String?> link(String workout) async {
        final rows = await h.exec('SELECT template_id::text FROM workouts WHERE id = @w::uuid', {'w': workout});
        return rows.single[0] as String?;
      }

      const insertTemplate = "INSERT INTO templates (id, user_id, name, order_index) VALUES (@t::uuid, @u, 'A', 0)";
      const insertWorkout = '''
        INSERT INTO workouts (id, user_id, name, sent_template_id) VALUES (@w::uuid, @u, 'A', @t::uuid)
      ''';
      for (final workoutFirst in [true, false]) {
        final (t, w) = (uuidV7(), uuidV7());
        final [first, second] = workoutFirst ? [insertWorkout, insertTemplate] : [insertTemplate, insertWorkout];
        Map<String, dynamic> params(String sql) => {'t': t, 'u': userId, if (sql == insertWorkout) 'w': w};

        late Future<void> waiting;
        await h.pool.runTx((tx) async {
          await tx.execute(Sql.named(first), parameters: params(first));
          // on its own connection: it waits for this transaction to end
          waiting = h.exec(second, params(second));
          await Future<void>.delayed(const Duration(milliseconds: 200));
        });
        await waiting;
        expect(await link(w), t, reason: workoutFirst ? 'the workout first' : 'the template first');
      }
    });

    test('a session put back takes the place of the one sent with', () async {
      final coach = await h.seedProfile();
      final (program, session) = await seedProgram(userId);
      await h.exec('UPDATE programs SET coach_id = @c WHERE id = @p::uuid', {'c': coach, 'p': program});
      final workout = await save({'templateId': session, 'programId': program});
      await h.db.removeSession(ownerId: userId, actorId: userId, sessionId: session);
      await h.db.updateWorkout(
        userId: userId,
        workoutId: workout.id,
        body: body({'templateId': sample}),
        imageUrl: imageUrl,
      );
      await h.db.restoreSession(
        ownerId: userId,
        actorId: userId,
        programId: program,
        body: TemplateRequest(userId: userId, id: session, name: 'A'),
        links: {
          'workouts': [workout.id],
        },
      );
      final row = await h.exec('SELECT template_id::text, sent_template_id FROM workouts WHERE id = @w::uuid', {
        'w': workout.id,
      });
      expect(row.single, [session, null]);
    });

    test('one that arrives later is linked, and let go once deleted', () async {
      final id = uuidV7();
      final workout = await save({'templateId': id});
      expect(workout.templateId, id);

      await template(id: id);
      final linked = await h.exec('SELECT template_id::text FROM workouts WHERE id = @w::uuid', {'w': workout.id});
      expect(linked.single[0], id);
      expect(await read(workout.id), id);

      await h.db.deleteTemplate(coachId: userId, templateId: id);
      expect(await read(workout.id), isNull);
    });

    test('one deleted before the workout arrived is none, and so is a replace naming it', () async {
      final id = await template();
      await h.db.deleteTemplate(coachId: userId, templateId: id);

      final workout = await save({'templateId': id});
      expect(workout.templateId, isNull);
      final replaced = await h.db.updateWorkout(
        userId: userId,
        workoutId: workout.id,
        body: body({'templateId': id}),
        imageUrl: imageUrl,
      );
      expect(replaced.templateId, isNull);
      expect(await read(workout.id), isNull);
    });
  });

  test('a replace without the keys keeps them, as a 1.13 save does; null lets go', () async {
    final (program, template) = await seedProgram(userId);
    final (workout, _) = await h.db.createWorkout(
      userId: userId,
      body: body({'templateId': template, 'programId': program}),
      imageUrl: imageUrl,
    );

    final kept = await h.db.updateWorkout(userId: userId, workoutId: workout.id, body: body({}), imageUrl: imageUrl);
    expect((kept.templateId, kept.programId), (template, program));

    final cleared = await h.db.updateWorkout(
      userId: userId,
      workoutId: workout.id,
      body: body({'templateId': null, 'programId': null}),
      imageUrl: imageUrl,
    );
    expect(cleared.templateId, isNull);
    expect(cleared.programId, isNull);
  });

  test('deleting the session keeps the program; deleting the program lets go of both', () async {
    final (program, template) = await seedProgram(userId);
    final (workout, _) = await h.db.createWorkout(
      userId: userId,
      body: body({'templateId': template, 'programId': program}),
      imageUrl: imageUrl,
    );

    await h.db.deleteTemplate(coachId: userId, templateId: template);
    final afterSession = await h.db.getWorkout(userId: userId, workoutId: workout.id, imageUrl: imageUrl);
    expect(afterSession.templateId, isNull);
    expect(afterSession.programId, program);

    await h.db.deleteProgram(userId: userId, programId: program);
    final afterProgram = await h.db.getWorkout(userId: userId, workoutId: workout.id, imageUrl: imageUrl);
    expect(afterProgram.programId, isNull);
  });

  test('a superset is stored on a logged exercise and kept by a replace that leaves it out (heart-api#234)', () async {
    final exerciseId = await h.seedGlobalExercise();
    final exerciseRowId = uuidV7();
    WorkoutRequest grouped(Map<String, dynamic> extra) => WorkoutRequest(
      userId: userId,
      body: {
        'name': 'Arms',
        'start': DateTime.utc(2026, 10, 15, 18).toIso8601String(),
        'exercises': [
          {
            'id': exerciseRowId,
            'exercise': exerciseId,
            'order': 0,
            ...extra,
            'sets': [
              {'reps': 10, 'completed': true},
            ],
          },
        ],
      },
    );

    final (workout, _) = await h.db.createWorkout(userId: userId, body: grouped({'superset': 2}), imageUrl: imageUrl);
    expect(workout.single.superset, 2);
    final kept = await h.db.updateWorkout(userId: userId, workoutId: workout.id, body: grouped({}), imageUrl: imageUrl);
    expect(kept.single.superset, 2);
    final read = await h.db.getWorkout(userId: userId, workoutId: workout.id, imageUrl: imageUrl);
    expect(read.single.superset, 2);
  });
}

class _Harness extends DatabaseTestBase;
