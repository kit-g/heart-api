@Tags(['db'])
library;

import 'package:heart/models/changes.dart';
import 'package:heart/models/errors.dart';
import 'package:postgres/postgres.dart';
import 'package:heart_models/heart_models.dart';
import 'package:test/test.dart';

import 'db_test_utility.dart';

/// The workout change feed, the record sets and an exercise's history
/// against a live Postgres: ordering by transaction, the cursor, deletions,
/// open transactions, and which sets count toward a record or a session.
///
/// Tagged `db` — skipped by the default `dart test`. Run with:
///   dart test --run-skipped -t db
void main() {
  final h = _Harness();

  setUpAll(h.setupDatabase);
  tearDownAll(h.teardownDatabase);

  Future<WorkoutChanges> changes(
    String userId, {
    ChangeCursor? since,
    int limit = 100,
  }) {
    return h.db.getWorkoutChanges(userId: userId, since: since, limit: limit, imageUrl: (k) => k);
  }

  /// Polls until [done] holds. The feed waits for every transaction still
  /// writing, and the other suites run theirs in parallel against the same
  /// database: what is due shows up once they finish, not instantly.
  Future<WorkoutChanges> eventually(
    Future<WorkoutChanges> Function() read,
    bool Function(WorkoutChanges) done,
  ) async {
    final deadline = DateTime.now().add(const Duration(seconds: 10));
    while (true) {
      final result = await read();
      if (done(result) || DateTime.now().isAfter(deadline)) return result;
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
  }

  group('getWorkoutChanges', () {
    test('lists changes oldest first, and an up-to-date cursor finds nothing new', () async {
      final user = await h.seedProfile();
      final older = await h.seedWorkout(userId: user, name: 'older', withExercise: true);
      final newer = await h.seedWorkout(userId: user, name: 'newer');

      final first = await eventually(() => changes(user), (c) => c.upserted.length == 2);
      expect(first.upserted.map((w) => w.id), [older, newer]);
      expect(first.upserted.first.first.length, 1, reason: 'the workout comes whole');
      expect(first.deleted, isEmpty);
      expect(first.hasMore, isFalse);

      final again = await changes(user, since: first.cursor);
      expect(again.upserted, isEmpty);
      expect(again.cursor.toString(), first.cursor.toString(), reason: 'nothing new keeps the cursor');
    });

    test('an edit to a set brings its workout back', () async {
      final user = await h.seedProfile();
      final workout = await h.seedWorkout(userId: user, withExercise: true);
      final cursor = (await eventually(() => changes(user), (c) => c.upserted.isNotEmpty)).cursor;

      await h.exec(
        'UPDATE exercise_sets SET reps = 6 WHERE workout_exercise_id IN '
        '(SELECT id FROM workout_exercises WHERE workout_id = @w::uuid)',
        {'w': workout},
      );

      final after = await eventually(() => changes(user, since: cursor), (c) => c.upserted.isNotEmpty);
      expect(after.upserted.map((w) => w.id), [workout]);
    });

    test('a transaction that reads before it writes lands after the cursor, not behind it', () async {
      final user = await h.seedProfile();

      final cursor = await h.pool.runTx((tx) async {
        // started, read, but not written: no transaction id yet
        await tx.execute('SELECT 1');
        // meanwhile another save commits, and a poller takes the cursor past it
        await h.seedWorkout(userId: user, name: 'meanwhile');
        final polled = await eventually(() => changes(user), (c) => c.upserted.isNotEmpty);
        expect(polled.upserted.map((w) => w.name), ['meanwhile']);

        await tx.execute(
          Sql.named('INSERT INTO workouts (user_id, name, started_at) VALUES (@u, @n, now())'),
          parameters: {'u': user, 'n': 'late'},
        );
        return polled.cursor;
      });

      final after = await eventually(() => changes(user, since: cursor), (c) => c.upserted.isNotEmpty);
      expect(after.upserted.map((w) => w.name), ['late'], reason: 'its stamp is its write, after the cursor');
    });

    test('a transaction still writing holds back everything newer, whatever its length', () async {
      final user = await h.seedProfile();
      await h.seedWorkout(userId: user, name: 'settled');

      await h.pool.runTx((tx) async {
        // a long save in flight: it has written (so it has a transaction
        // id) and not committed; everything after it waits
        await tx.execute('SELECT txid_current()');
        await Future<void>.delayed(const Duration(milliseconds: 50));

        await h.seedWorkout(userId: user, name: 'newer');
        final during = await changes(user);
        expect(during.upserted.map((w) => w.name), ['settled'], reason: 'newer than the open transaction');
      });

      final after = await eventually(() => changes(user), (c) => c.upserted.length == 2);
      expect(after.upserted.map((w) => w.name), ['settled', 'newer']);
    });

    test('a deleted workout is reported once, by id', () async {
      final user = await h.seedProfile();
      await h.seedWorkout(userId: user, name: 'kept');
      final gone = await h.seedWorkout(userId: user, name: 'gone');
      final cursor = (await eventually(() => changes(user), (c) => c.upserted.length == 2)).cursor;

      await h.exec('DELETE FROM workouts WHERE id = @id::uuid', {'id': gone});

      final after = await eventually(() => changes(user, since: cursor), (c) => c.deleted.isNotEmpty);
      expect(after.upserted, isEmpty);
      expect(after.deleted.map((d) => d.id), [gone]);
      expect((await changes(user, since: after.cursor)).deleted, isEmpty);
    });

    test('pages are cut at the limit and continue from the cursor', () async {
      final user = await h.seedProfile();
      final ids = <String>[];
      for (var i = 0; i < 3; i++) {
        final id = await h.seedWorkout(userId: user, name: 'w$i');
        ids.add(id);
      }

      final first = await eventually(() => changes(user, limit: 2), (c) => c.hasMore);
      expect(first.upserted.map((w) => w.id), ids.take(2));
      expect(first.hasMore, isTrue);

      final second = await changes(user, since: first.cursor, limit: 2);
      expect(second.upserted.map((w) => w.id), [ids.last]);
      expect(second.hasMore, isFalse);
    });

    test('a cursor from another database (its transaction past ours) is stale, never read from', () async {
      final user = await h.seedProfile();
      await h.seedWorkout(userId: user);
      const moved = ChangeCursor(xid: '9000000000000000000', id: '019a0000-0000-7000-8000-000000000001');

      await expectLater(
        changes(user, since: moved),
        throwsA(isA<BadRequest>().having((e) => e.code, 'code', 'stale_cursor')),
      );
    });

    test("another account's changes never show", () async {
      final mine = await h.seedProfile();
      final theirs = await h.seedProfile();
      await h.seedWorkout(userId: theirs);
      expect((await changes(mine)).upserted, isEmpty);
    });
  });

  group('getRecordSets', () {
    test('only completed working sets count, oldest first, per exercise', () async {
      final user = await h.seedProfile();
      final exercise = await h.seedGlobalExercise();
      Future<void> session(DateTime start, List<(double, int, String?, bool)> sets) async {
        final workout = await h.seedWorkout(userId: user, start: start, end: start.add(const Duration(hours: 1)));
        final we = await h.insertId(
          'INSERT INTO workout_exercises (workout_id, exercise_id, exercise_order) VALUES (@w, @e, 0) RETURNING id',
          {'w': workout, 'e': exercise},
        );
        for (final (i, (weight, reps, type, completed)) in sets.indexed) {
          await h.exec(
            'INSERT INTO exercise_sets (workout_exercise_id, weight, reps, set_order, set_type, completed) '
            'VALUES (@we, @w, @r, @o, @t, @c)',
            {'we': we, 'w': weight, 'r': reps, 'o': i, 't': type, 'c': completed},
          );
        }
      }

      await session(DateTime.utc(2026, 1, 1), [(140, 1, 'w', true), (100, 5, null, true), (120, 1, null, false)]);
      await session(DateTime.utc(2026, 2, 1), [(105, 5, 'f', true)]);

      final sets = await h.db.getRecordSets(userId: user, exerciseId: exercise);
      expect(sets, hasLength(1));
      final only = sets.single;
      expect(only.category, Category.barbell);
      expect(only.sets.map((s) => s.weight), [100, 105], reason: 'no warm-up, nothing incomplete');

      final records = only.sets.toPersonalRecords(only.category)!;
      expect((records['heaviest']! as Map)['weight'], 105);
      expect(records['sessions'], 2);

      await h.exec('DELETE FROM workouts WHERE user_id = @u', {'u': user});
    });

    test('a window keeps to workouts started in it, from inclusive, to exclusive', () async {
      final user = await h.seedProfile();
      final exercise = await h.seedGlobalExercise();
      for (final (month, weight) in [(1, 100.0), (2, 120.0), (3, 110.0)]) {
        final start = DateTime.utc(2026, month);
        final workout = await h.seedWorkout(userId: user, start: start, end: start.add(const Duration(hours: 1)));
        final we = await h.insertId(
          'INSERT INTO workout_exercises (workout_id, exercise_id, exercise_order) VALUES (@w, @e, 0) RETURNING id',
          {'w': workout, 'e': exercise},
        );
        await h.exec(
          'INSERT INTO exercise_sets (workout_exercise_id, weight, reps, set_order, completed) VALUES (@we, @w, 5, 0, true)',
          {'we': we, 'w': weight},
        );
      }

      Future<List<double?>> weights({DateTime? from, DateTime? to}) async {
        final sets = await h.db.getRecordSets(userId: user, exerciseId: exercise, from: from, to: to);
        return [for (final set in sets.singleOrNull?.sets ?? const <RecordSet>[]) set.weight];
      }

      expect(await weights(), [100, 120, 110]);
      expect(await weights(from: DateTime.utc(2026, 2)), [120, 110], reason: 'from is inclusive');
      expect(await weights(to: DateTime.utc(2026, 3)), [100, 120], reason: 'to is exclusive');
      expect(await weights(from: DateTime.utc(2026, 3), to: DateTime.utc(2026, 4)), [110]);
      expect(await weights(from: DateTime.utc(2027)), isEmpty);

      final history = (await h.db.getExerciseHistory(
        userId: user,
        exerciseId: exercise,
        from: DateTime.utc(2026, 2),
        to: DateTime.utc(2026, 3),
      ))!;
      expect([for (final session in history.sessions.items) session.at], ['2026-02-01T00:00:00.000Z']);

      await h.exec('DELETE FROM workouts WHERE user_id = @u', {'u': user});
    });

    test('a workout without a start counts from when it was created', () async {
      final user = await h.seedProfile();
      final exercise = await h.seedGlobalExercise();
      final workout = await h.insertId(
        'INSERT INTO workouts (user_id, name) VALUES (@u, @n) RETURNING id',
        {'u': user, 'n': 'no start'},
      );
      final we = await h.insertId(
        'INSERT INTO workout_exercises (workout_id, exercise_id, exercise_order) VALUES (@w, @e, 0) RETURNING id',
        {'w': workout, 'e': exercise},
      );
      await h.exec(
        'INSERT INTO exercise_sets (workout_exercise_id, weight, reps, set_order, completed) VALUES (@we, 50, 5, 0, true)',
        {'we': we},
      );

      final sets = (await h.db.getRecordSets(userId: user, exerciseId: exercise)).single.sets;
      expect(sets.single.at, isNotEmpty);

      await h.exec('DELETE FROM workouts WHERE user_id = @u', {'u': user});
    });
  });

  group('getExerciseHistory', () {
    /// A workout at [start] doing [exercise] with [sets] (weight, reps, set
    /// type, completed), in that order. Workouts are made oldest first, so
    /// their ids follow their starts the way the app's and imports' do.
    Future<String> perform(
      String user,
      String exercise,
      DateTime start,
      List<(double, int, String?, bool)> sets,
    ) async {
      final workout = await h.seedWorkout(userId: user, start: start, end: start.add(const Duration(hours: 1)));
      final we = await h.insertId(
        'INSERT INTO workout_exercises (workout_id, exercise_id, exercise_order) VALUES (@w, @e, 0) RETURNING id',
        {'w': workout, 'e': exercise},
      );
      for (final (i, (weight, reps, type, completed)) in sets.indexed) {
        await h.exec(
          'INSERT INTO exercise_sets (workout_exercise_id, weight, reps, set_order, set_type, completed) '
          'VALUES (@we, @w, @r, @o, @t, @c)',
          {'we': we, 'w': weight, 'r': reps, 'o': i, 't': type, 'c': completed},
        );
      }
      return workout;
    }

    test('sessions newest first, each with its working sets in order', () async {
      final user = await h.seedProfile();
      final exercise = await h.seedGlobalExercise();
      final january = await perform(user, exercise, DateTime.utc(2026, 1, 1), [
        (60, 10, 'w', true),
        (100, 5, null, true),
        (110, 3, null, true),
        (120, 1, null, false),
      ]);
      final february = await perform(user, exercise, DateTime.utc(2026, 2, 1), [(105, 5, 'f', true)]);
      // a session of nothing but warm-ups isn't a session of this exercise
      await perform(user, exercise, DateTime.utc(2026, 3, 1), [(60, 10, 'w', true)]);

      final history = (await h.db.getExerciseHistory(userId: user, exerciseId: exercise))!;
      expect(history.category, Category.barbell);
      expect(history.sessions.hasMore, isFalse);
      expect(history.sessions.items.map((s) => s.workoutId), [february, january]);
      expect(history.sessions.items.last.sets.map((s) => (s.weight, s.reps)), [(100, 5), (110, 3)]);
      expect(history.sessions.items.first.at, '2026-02-01T00:00:00.000Z');

      await h.exec('DELETE FROM workouts WHERE user_id = @u', {'u': user});
    });

    test('pages continue from the last workout id', () async {
      final user = await h.seedProfile();
      final exercise = await h.seedGlobalExercise();
      final ids = [
        for (var month = 1; month <= 3; month++)
          await perform(user, exercise, DateTime.utc(2026, month), [(100, 5, null, true), (100, 5, null, true)]),
      ];

      final first = (await h.db.getExerciseHistory(userId: user, exerciseId: exercise, limit: 2))!.sessions;
      expect(first.items.map((s) => s.workoutId), [ids[2], ids[1]]);
      expect(first.hasMore, isTrue);
      // two sets a session: the limit counts sessions, not rows
      expect(first.items.every((s) => s.sets.length == 2), isTrue);

      final rest = (await h.db.getExerciseHistory(
        userId: user,
        exerciseId: exercise,
        limit: 2,
        cursor: first.items.last.workoutId,
      ))!.sessions;
      expect(rest.items.map((s) => s.workoutId), [ids[0]]);
      expect(rest.hasMore, isFalse);

      await h.exec('DELETE FROM workouts WHERE user_id = @u', {'u': user});
    });

    test("never done is an empty page; someone else's exercise is nothing at all", () async {
      final user = await h.seedProfile();
      final other = await h.seedProfile();
      final exercise = await h.seedGlobalExercise();
      final theirs = await h.insertId(
        'INSERT INTO exercises (name, category, target, user_id) VALUES (@n, @c, @t, @u) RETURNING id',
        {'n': h.uniqueName('Theirs'), 'c': 'Barbell', 't': 'Chest', 'u': other},
      );
      await perform(other, exercise, DateTime.utc(2026, 1, 1), [(100, 5, null, true)]);

      final never = (await h.db.getExerciseHistory(userId: user, exerciseId: exercise))!;
      expect(never.sessions.items, isEmpty, reason: "another account's sessions never show");
      expect(never.name, isNotEmpty);
      expect(await h.db.getExerciseHistory(userId: user, exerciseId: theirs), isNull);

      await h.exec('DELETE FROM workouts WHERE user_id = @u', {'u': other});
      await h.exec('DELETE FROM exercises WHERE id = @id::uuid', {'id': theirs});
    });
  });
}

class _Harness extends DatabaseTestBase;
