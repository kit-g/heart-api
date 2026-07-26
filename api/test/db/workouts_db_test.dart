@Tags(['db'])
library;

import 'package:heart/models/errors.dart';
import 'package:heart/models/workouts.dart';
import 'package:postgres/postgres.dart' hide Connection;
import 'package:test/test.dart';

import 'db_test_utility.dart';

/// Full integration coverage of the `ApiWorkoutService` query strings against a
/// live Postgres: create/read/list/update/patch/delete, plus the owner- and
/// connection-based access rules the SQL encodes.
///
/// Tagged `db` — skipped by the default `dart test` (no database). Run with:
///   dart test --run-skipped -t db
void main() {
  final harness = _Harness();

  final suffix = DateTime.now().microsecondsSinceEpoch.toString();
  final ownerId = 'itest-wk-owner-$suffix';
  final peerId = 'itest-wk-peer-$suffix'; // connected to owner
  final strangerId = 'itest-wk-stranger-$suffix'; // not connected
  final listOwnerId = 'itest-wk-list-$suffix'; // isolated, for pagination
  final createdExercises = <String>[];
  var exCount = 0;

  String imageUrl(String key) => 'https://cdn.test/$key';
  String uniqueExerciseName() => 'ITest WK Ex ${exCount++}-$suffix';

  Future<void> exec(String sql, [Map<String, dynamic> params = const {}]) async {
    await harness.pool.execute(Sql.named(sql), parameters: params);
  }

  Future<String> insertReturningId(String sql, Map<String, dynamic> params) async {
    final rows = await harness.pool.execute(Sql.named(sql), parameters: params);
    return rows.first.toColumnMap()['id'].toString();
  }

  Future<String> seedExercise(String name) async {
    final id = await insertReturningId(
      'INSERT INTO exercises (name, category, target) VALUES (@n, @c, @t) RETURNING id',
      {'n': name, 'c': 'Barbell', 't': 'Chest'},
    );
    createdExercises.add(id);
    return id;
  }

  /// Raw-inserts a workout owned by [userId] with one exercise + one set.
  Future<String> seedWorkout(String userId, {String name = 'Original', DateTime? start, DateTime? end}) async {
    final workoutId = await insertReturningId(
      'INSERT INTO workouts (user_id, name, started_at, completed_at) VALUES (@u, @n, @s, @e) RETURNING id',
      {'u': userId, 'n': name, 's': start ?? DateTime.utc(2026, 7, 20, 18), 'e': end ?? DateTime.utc(2026, 7, 20, 19)},
    );
    final exerciseId = await seedExercise(uniqueExerciseName());
    final weId = await insertReturningId(
      'INSERT INTO workout_exercises (workout_id, exercise_id, exercise_order) VALUES (@w, @e, 0) RETURNING id',
      {'w': workoutId, 'e': exerciseId},
    );
    await exec(
      'INSERT INTO exercise_sets (workout_exercise_id, weight, reps, set_order) VALUES (@we, 100, 5, 0)',
      {'we': weId},
    );
    return workoutId;
  }

  /// A create/update request body referencing [exerciseName] (which must already
  /// exist so the query can resolve name → id).
  Map<String, dynamic> reqBody({
    required String name,
    required DateTime start,
    DateTime? end,
    required String exerciseName,
  }) {
    return {
      'name': name,
      'start': start.toIso8601String(),
      if (end != null) 'end': end.toIso8601String(),
      'exercises': [
        {
          'exercise': exerciseName,
          'order': 0,
          'sets': [
            {'weight': 100, 'reps': 5, 'completed': true},
          ],
        },
      ],
    };
  }

  setUpAll(() async {
    await harness.setupDatabase();
    for (final id in [ownerId, peerId, strangerId, listOwnerId]) {
      await exec('INSERT INTO profiles (id, username, email) VALUES (@id, @u, @e)', {
        'id': id,
        'u': 'wk_${id}_$suffix',
        'e': '$id@test.local',
      });
    }
    // peer ↔ owner are connected as peers; stranger is left unconnected.
    await exec(
      'INSERT INTO connections (initiator_id, target_id, initiator_role, target_role, domain, status) '
      "VALUES (@p, @o, 'PEER', 'PEER', 'fitness', 'active')",
      {'p': peerId, 'o': ownerId},
    );
  });

  tearDownAll(() async {
    await exec('DELETE FROM profiles WHERE id = ANY(@ids)', {
      'ids': [ownerId, peerId, strangerId, listOwnerId],
    });
    for (final id in createdExercises) {
      await exec('DELETE FROM exercises WHERE id = @id::uuid', {'id': id});
    }
    await harness.teardownDatabase();
  });

  group('createWorkout', () {
    test('persists the workout with its resolved exercise and set', () async {
      final exName = uniqueExerciseName();
      await seedExercise(exName);

      final created = await harness.db.createWorkout(
        userId: ownerId,
        body: WorkoutRequest(
          userId: ownerId,
          body: reqBody(
            name: 'New workout',
            start: DateTime.utc(2026, 7, 25, 10),
            end: DateTime.utc(2026, 7, 25, 11),
            exerciseName: exName,
          ),
        ),
        imageUrl: imageUrl,
      );

      expect(created.name, 'New workout');
      expect(created.start.toUtc(), DateTime.utc(2026, 7, 25, 10));
      expect(created.end?.toUtc(), DateTime.utc(2026, 7, 25, 11));
      expect(created.length, 1); // one exercise
      expect(created.first.exercise.name, exName);
      expect(created.first.length, 1); // one set
    });
  });

  group('getWorkout', () {
    test('the owner reads their workout with exercises', () async {
      final id = await seedWorkout(ownerId);
      final w = await harness.db.getWorkout(userId: ownerId, workoutId: id, imageUrl: imageUrl);
      expect(w.id, id);
      expect(w.length, 1);
    });

    test('another user cannot read it (NotFound)', () async {
      final id = await seedWorkout(ownerId);
      await expectLater(
        harness.db.getWorkout(userId: strangerId, workoutId: id, imageUrl: imageUrl),
        throwsA(isA<NotFound>()),
      );
    });
  });

  group('getTargetWorkout', () {
    test('a connected requester reads the target workout', () async {
      final id = await seedWorkout(ownerId);
      final w = await harness.db.getTargetWorkout(
        requesterId: peerId,
        targetUserId: ownerId,
        workoutId: id,
        imageUrl: imageUrl,
      );
      expect(w.id, id);
    });

    test('an unconnected requester is Forbidden', () async {
      final id = await seedWorkout(ownerId);
      await expectLater(
        harness.db.getTargetWorkout(
          requesterId: strangerId,
          targetUserId: ownerId,
          workoutId: id,
          imageUrl: imageUrl,
        ),
        throwsA(isA<Forbidden>()),
      );
    });

    test('a connected requester gets NotFound for a missing workout', () async {
      await expectLater(
        harness.db.getTargetWorkout(
          requesterId: peerId,
          targetUserId: ownerId,
          workoutId: '00000000-0000-7000-8000-000000000000',
          imageUrl: imageUrl,
        ),
        throwsA(isA<NotFound>()),
      );
    });
  });

  group('getWorkouts', () {
    test('lists an isolated owner newest-first with limit+1 pagination', () async {
      final w1 = await seedWorkout(listOwnerId, name: 'W1');
      final w2 = await seedWorkout(listOwnerId, name: 'W2');

      final page1 = await harness.db.getWorkouts(
        userId: listOwnerId,
        targetUserId: listOwnerId,
        limit: 1,
        imageUrl: imageUrl,
      );
      expect(page1.items, hasLength(1));
      expect(page1.hasMore, isTrue);
      expect(page1.items.single.id, w2); // uuidv7 → newest first

      final page2 = await harness.db.getWorkouts(
        userId: listOwnerId,
        targetUserId: listOwnerId,
        cursor: page1.items.single.id,
        limit: 1,
        imageUrl: imageUrl,
      );
      expect(page2.items.single.id, w1);
      expect(page2.hasMore, isFalse);
    });

    test('a connected requester may list the target', () async {
      await seedWorkout(ownerId);
      final page = await harness.db.getWorkouts(
        userId: peerId,
        targetUserId: ownerId,
        limit: 10,
        imageUrl: imageUrl,
      );
      expect(page.items, isNotEmpty);
    });

    test('an unconnected requester is Forbidden', () async {
      await expectLater(
        harness.db.getWorkouts(userId: strangerId, targetUserId: ownerId, limit: 10, imageUrl: imageUrl),
        throwsA(isA<Forbidden>()),
      );
    });
  });

  group('updateWorkout', () {
    test('replaces the times, name, and exercises', () async {
      final exA = uniqueExerciseName();
      await seedExercise(exA);
      final id = (await harness.db.createWorkout(
        userId: ownerId,
        body: WorkoutRequest(
          userId: ownerId,
          body: reqBody(name: 'V1', start: DateTime.utc(2026, 7, 25, 8), exerciseName: exA),
        ),
        imageUrl: imageUrl,
      )).id;

      final exB = uniqueExerciseName();
      await seedExercise(exB);
      final updated = await harness.db.updateWorkout(
        userId: ownerId,
        workoutId: id,
        body: WorkoutRequest(
          userId: ownerId,
          body: reqBody(
            name: 'V2',
            start: DateTime.utc(2026, 7, 25, 9),
            end: DateTime.utc(2026, 7, 25, 10),
            exerciseName: exB,
          ),
        ),
        imageUrl: imageUrl,
      );

      expect(updated.name, 'V2');
      expect(updated.start.toUtc(), DateTime.utc(2026, 7, 25, 9));
      expect(updated.length, 1);
      expect(updated.first.exercise.name, exB); // A replaced by B
    });

    test('updating a workout you do not own throws NotFound', () async {
      final id = await seedWorkout(ownerId);
      await expectLater(
        harness.db.updateWorkout(
          userId: strangerId,
          workoutId: id,
          body: WorkoutRequest(
            userId: strangerId,
            body: reqBody(name: 'hijack', start: DateTime.utc(2026, 7, 25, 9), exerciseName: 'nonexistent'),
          ),
          imageUrl: imageUrl,
        ),
        throwsA(isA<NotFound>()),
      );
    });
  });

  group('deleteWorkout', () {
    test('the owner deletes their workout', () async {
      final id = await seedWorkout(ownerId);
      await harness.db.deleteWorkout(userId: ownerId, workoutId: id);
      await expectLater(
        harness.db.getWorkout(userId: ownerId, workoutId: id, imageUrl: imageUrl),
        throwsA(isA<NotFound>()),
      );
    });

    test('deleting a workout you do not own is a no-op', () async {
      final id = await seedWorkout(ownerId);
      await harness.db.deleteWorkout(userId: strangerId, workoutId: id);
      final w = await harness.db.getWorkout(userId: ownerId, workoutId: id, imageUrl: imageUrl);
      expect(w.id, id); // still there
    });
  });

  group('patchWorkout', () {
    test('updates only the provided fields and preserves exercises', () async {
      final id = await seedWorkout(ownerId);
      final newStart = DateTime.utc(2026, 7, 20, 17, 30);
      final newEnd = DateTime.utc(2026, 7, 20, 18, 45);

      final updated = await harness.db.patchWorkout(
        userId: ownerId,
        workoutId: id,
        name: 'Evening push',
        start: newStart,
        end: newEnd,
        imageUrl: imageUrl,
      );

      expect(updated.name, 'Evening push');
      expect(updated.start.toUtc(), newStart);
      expect(updated.end?.toUtc(), newEnd);
      expect(updated.length, 1); // exercise untouched
    });

    test('leaves omitted fields unchanged (name-only patch keeps the times)', () async {
      final id = await seedWorkout(ownerId);

      final updated = await harness.db.patchWorkout(
        userId: ownerId,
        workoutId: id,
        name: 'Renamed only',
        imageUrl: imageUrl,
      );

      expect(updated.name, 'Renamed only');
      expect(updated.start.toUtc(), DateTime.utc(2026, 7, 20, 18)); // original
      expect(updated.end?.toUtc(), DateTime.utc(2026, 7, 20, 19)); // original
    });

    test('does not touch a workout owned by someone else', () async {
      final id = await seedWorkout(ownerId);
      await expectLater(
        harness.db.patchWorkout(userId: strangerId, workoutId: id, name: 'Hijacked', imageUrl: imageUrl),
        throwsA(isA<NotFound>()),
      );
      final owned = await harness.db.getWorkout(userId: ownerId, workoutId: id, imageUrl: imageUrl);
      expect(owned.name, 'Original');
    });
  });
}

class _Harness extends DatabaseTestBase {}
