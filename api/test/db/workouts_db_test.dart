@Tags(['db'])
library;

import 'package:heart/models/errors.dart';
import 'package:postgres/postgres.dart' hide Connection;
import 'package:test/test.dart';

import 'db_test_utility.dart';

/// Exercises the real `patchWorkout` query against a live Postgres: partial
/// updates of name/start/end, exercises left intact, and owner scoping.
///
/// Tagged `db` — skipped by the default `dart test` (no database). Run with:
///   dart test --run-skipped -t db
void main() {
  final harness = _Harness();

  final suffix = DateTime.now().microsecondsSinceEpoch.toString();
  final ownerId = 'itest-wk-owner-$suffix';
  final otherId = 'itest-wk-other-$suffix';
  final createdExercises = <String>[];
  var seedCount = 0;
  String imageUrl(String key) => 'https://cdn.test/$key';

  Future<void> exec(String sql, [Map<String, dynamic> params = const {}]) async {
    await harness.pool.execute(Sql.named(sql), parameters: params);
  }

  /// Seeds a completed workout owned by [ownerId] with one exercise + set, and
  /// returns its id.
  Future<String> seedWorkout() async {
    final n = seedCount++;
    final wk = await harness.pool.execute(
      Sql.named(
        'INSERT INTO workouts (user_id, name, started_at, completed_at) '
        "VALUES (@u, 'Original', @s, @e) RETURNING id",
      ),
      parameters: {
        'u': ownerId,
        's': DateTime.utc(2026, 7, 20, 18),
        'e': DateTime.utc(2026, 7, 20, 19),
      },
    );
    final workoutId = wk.first.toColumnMap()['id'].toString();

    // Global exercises are unique by name, so vary it per seeded workout.
    final ex = await harness.pool.execute(
      Sql.named('INSERT INTO exercises (name, category, target) VALUES (@n, @c, @t) RETURNING id'),
      parameters: {'n': 'ITest Bench $n-$suffix', 'c': 'Barbell', 't': 'Chest'},
    );
    final exerciseId = ex.first.toColumnMap()['id'].toString();
    createdExercises.add(exerciseId);

    final we = await harness.pool.execute(
      Sql.named(
        'INSERT INTO workout_exercises (workout_id, exercise_id, exercise_order) '
        'VALUES (@w, @e, 0) RETURNING id',
      ),
      parameters: {'w': workoutId, 'e': exerciseId},
    );
    final weId = we.first.toColumnMap()['id'].toString();

    await exec(
      'INSERT INTO exercise_sets (workout_exercise_id, weight, reps, set_order) VALUES (@we, 100, 5, 0)',
      {'we': weId},
    );
    return workoutId;
  }

  setUpAll(() async {
    await harness.setupDatabase();
    for (final id in [ownerId, otherId]) {
      await exec('INSERT INTO profiles (id, username, email) VALUES (@id, @u, @e)', {
        'id': id,
        'u': 'wk_${id}_$suffix',
        'e': '$id@test.local',
      });
    }
  });

  tearDownAll(() async {
    // Delete profiles first: workouts/workout_exercises cascade away, freeing
    // the global exercises (which have no owner to cascade from) to be removed.
    await exec('DELETE FROM profiles WHERE id = ANY(@ids)', {
      'ids': [ownerId, otherId],
    });
    for (final id in createdExercises) {
      await exec('DELETE FROM exercises WHERE id = @id::uuid', {'id': id});
    }
    await harness.teardownDatabase();
  });

  test('updates only the provided fields and preserves exercises', () async {
    final workoutId = await seedWorkout();
    final newStart = DateTime.utc(2026, 7, 20, 17, 30);
    final newEnd = DateTime.utc(2026, 7, 20, 18, 45);

    final updated = await harness.db.patchWorkout(
      userId: ownerId,
      workoutId: workoutId,
      name: 'Evening push',
      start: newStart,
      end: newEnd,
      imageUrl: imageUrl,
    );

    expect(updated.name, 'Evening push');
    expect(updated.start.toUtc(), newStart);
    expect(updated.end?.toUtc(), newEnd);
    // The exercise the update didn't touch is still there.
    expect(updated.length, 1);
  });

  test('leaves omitted fields unchanged (name-only patch keeps the times)', () async {
    final workoutId = await seedWorkout();

    final updated = await harness.db.patchWorkout(
      userId: ownerId,
      workoutId: workoutId,
      name: 'Renamed only',
      start: null,
      end: null,
      imageUrl: imageUrl,
    );

    expect(updated.name, 'Renamed only');
    expect(updated.start.toUtc(), DateTime.utc(2026, 7, 20, 18)); // original
    expect(updated.end?.toUtc(), DateTime.utc(2026, 7, 20, 19)); // original
  });

  test('does not touch a workout owned by someone else', () async {
    final workoutId = await seedWorkout();

    await expectLater(
      harness.db.patchWorkout(
        userId: otherId,
        workoutId: workoutId,
        name: 'Hijacked',
        start: null,
        end: null,
        imageUrl: imageUrl,
      ),
      throwsA(isA<NotFound>()),
    );

    // And the owner's copy is untouched.
    final owned = await harness.db.getWorkout(userId: ownerId, workoutId: workoutId, imageUrl: imageUrl);
    expect(owned.name, 'Original');
  });
}

class _Harness extends DatabaseTestBase {}
