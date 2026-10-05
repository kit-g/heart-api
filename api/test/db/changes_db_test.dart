@Tags(['db'])
library;

import 'package:heart/models/changes.dart';
import 'package:heart_models/heart_models.dart';
import 'package:test/test.dart';

import 'db_test_utility.dart';

/// The workout change feed and the record sets against a live Postgres:
/// ordering, the cursor, deletions, the settle window, and which sets count
/// toward a record.
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
    Duration settle = Duration.zero,
  }) {
    return h.db.getWorkoutChanges(userId: userId, since: since, limit: limit, settle: settle, imageUrl: (k) => k);
  }

  Future<void> age(String workoutId, Duration ago) async {
    await h.exec(
      'UPDATE workouts SET updated_at = now() - make_interval(secs => @s) WHERE id = @id::uuid',
      {'s': ago.inSeconds, 'id': workoutId},
    );
  }

  group('getWorkoutChanges', () {
    test('lists changes oldest first, and an up-to-date cursor finds nothing new', () async {
      final user = await h.seedProfile();
      final older = await h.seedWorkout(userId: user, name: 'older', withExercise: true);
      final newer = await h.seedWorkout(userId: user, name: 'newer');
      await age(older, const Duration(hours: 2));
      await age(newer, const Duration(hours: 1));

      final first = await changes(user);
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
      await age(workout, const Duration(hours: 1));
      final cursor = (await changes(user)).cursor;

      await h.exec(
        'UPDATE exercise_sets SET reps = 6 WHERE workout_exercise_id IN '
        '(SELECT id FROM workout_exercises WHERE workout_id = @w::uuid)',
        {'w': workout},
      );

      expect((await changes(user, since: cursor)).upserted.map((w) => w.id), [workout]);
    });

    test('a change inside the settle window waits for a later poll', () async {
      final user = await h.seedProfile();
      await h.seedWorkout(userId: user);

      final held = await changes(user, settle: const Duration(minutes: 5));
      expect(held.upserted, isEmpty);
      expect(held.cursor, isNull);

      expect((await changes(user)).upserted, hasLength(1));
    });

    test('a deleted workout is reported once, by id', () async {
      final user = await h.seedProfile();
      final kept = await h.seedWorkout(userId: user, name: 'kept');
      final gone = await h.seedWorkout(userId: user, name: 'gone');
      await age(kept, const Duration(hours: 2));
      await age(gone, const Duration(hours: 2));
      final cursor = (await changes(user)).cursor;

      await h.exec('DELETE FROM workouts WHERE id = @id::uuid', {'id': gone});

      final after = await changes(user, since: cursor);
      expect(after.upserted, isEmpty);
      expect(after.deleted.map((d) => d.id), [gone]);
      expect((await changes(user, since: after.cursor)).deleted, isEmpty);
    });

    test('pages are cut at the limit and continue from the cursor', () async {
      final user = await h.seedProfile();
      final ids = <String>[];
      for (var i = 0; i < 3; i++) {
        final id = await h.seedWorkout(userId: user, name: 'w$i');
        await age(id, Duration(hours: 3 - i));
        ids.add(id);
      }

      final first = await changes(user, limit: 2);
      expect(first.upserted.map((w) => w.id), ids.take(2));
      expect(first.hasMore, isTrue);

      final second = await changes(user, since: first.cursor, limit: 2);
      expect(second.upserted.map((w) => w.id), [ids.last]);
      expect(second.hasMore, isFalse);
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

      final records = foldRecords(only.category, only.sets)!;
      expect((records['heaviest']! as Map)['weight'], 105);
      expect(records['sessions'], 2);

      await h.exec('DELETE FROM workouts WHERE user_id = @u', {'u': user});
    });
  });
}

class _Harness extends DatabaseTestBase;
