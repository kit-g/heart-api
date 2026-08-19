@Tags(['db'])
library;

import 'package:heart/models/errors.dart';
import 'package:heart/models/workouts.dart';
import 'package:test/test.dart';

import 'db_test_utility.dart';

/// Full integration coverage of the `ApiWorkoutService` query strings against a
/// live Postgres: create/read/list/update/patch/delete, plus the owner- and
/// connection-based access rules the SQL encodes.
///
/// Tagged `db` — skipped by the default `dart test`. Run with:
///   dart test --run-skipped -t db
void main() {
  final h = _Harness();

  late String ownerId;
  late String peerId; // connected to owner
  late String strangerId; // not connected
  late String listOwnerId; // isolated, for pagination

  String imageUrl(String key) => 'https://cdn.test/$key';

  /// A create/update request body referencing [exerciseName] (which must already
  /// exist so the query can resolve name → id).
  WorkoutRequest req(
    String userId, {
    required String name,
    required DateTime start,
    DateTime? end,
    required String exerciseName,
  }) {
    return WorkoutRequest(
      userId: userId,
      body: {
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
      },
    );
  }

  setUpAll(() async {
    await h.setupDatabase();
    ownerId = await h.seedProfile();
    peerId = await h.seedProfile();
    strangerId = await h.seedProfile();
    listOwnerId = await h.seedProfile();
    await h.seedConnection(initiator: peerId, target: ownerId);
  });

  tearDownAll(h.teardownDatabase);

  group('createWorkout', () {
    test('a workout stuffed past the DB set ceiling gets a 400, not a 500', () async {
      final exName = h.uniqueName('Ex');
      await h.seedGlobalExercise(name: exName);
      final stuffed = WorkoutRequest(
        userId: ownerId,
        body: {
          'name': 'Stuffed',
          'start': DateTime.utc(2026, 7, 25, 10).toIso8601String(),
          'exercises': [
            {
              'exercise': exName,
              'order': 0,
              'sets': [
                for (var n = 0; n < 1001; n++) {'weight': 100, 'reps': 5, 'completed': true},
              ],
            },
          ],
        },
      );

      await expectLater(
        h.db.createWorkout(userId: ownerId, body: stuffed, imageUrl: imageUrl),
        throwsA(isA<BadRequest>()),
      );
      // the refused write left no workout behind
      final count = await h.exec(
        "SELECT count(*)::int AS n FROM workouts WHERE user_id = @id AND name = 'Stuffed'",
        {'id': ownerId},
      );
      expect(count.first.toColumnMap()['n'], 0);
    });

    test('a workout stuffed with set-less exercise entries gets a 400, not a 500', () async {
      final exName = h.uniqueName('Ex');
      await h.seedGlobalExercise(name: exName);
      final stuffed = WorkoutRequest(
        userId: ownerId,
        body: {
          'name': 'Exercise-stuffed',
          'start': DateTime.utc(2026, 7, 25, 10).toIso8601String(),
          'exercises': [
            // empty sets, so the sets ceiling never sees these — the
            // workout_exercises ceiling must
            for (var n = 0; n < 1001; n++) {'exercise': exName, 'order': n, 'sets': <Object>[]},
          ],
        },
      );

      await expectLater(
        h.db.createWorkout(userId: ownerId, body: stuffed, imageUrl: imageUrl),
        throwsA(isA<BadRequest>()),
      );
    });

    test('persists the workout with its resolved exercise and set', () async {
      final exName = h.uniqueName('Ex');
      await h.seedGlobalExercise(name: exName);

      final created = await h.db.createWorkout(
        userId: ownerId,
        body: req(
          ownerId,
          name: 'New workout',
          start: DateTime.utc(2026, 7, 25, 10),
          end: DateTime.utc(2026, 7, 25, 11),
          exerciseName: exName,
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
      final id = await h.seedWorkout(userId: ownerId, withExercise: true);
      final w = await h.db.getWorkout(userId: ownerId, workoutId: id, imageUrl: imageUrl);
      expect(w.id, id);
      expect(w.length, 1);
    });

    test('another user cannot read it (NotFound)', () async {
      final id = await h.seedWorkout(userId: ownerId);
      await expectLater(
        h.db.getWorkout(userId: strangerId, workoutId: id, imageUrl: imageUrl),
        throwsA(isA<NotFound>()),
      );
    });
  });

  group('getTargetWorkout', () {
    test('a connected requester reads the target workout', () async {
      final id = await h.seedWorkout(userId: ownerId);
      final w = await h.db.getTargetWorkout(
        requesterId: peerId,
        targetUserId: ownerId,
        workoutId: id,
        imageUrl: imageUrl,
      );
      expect(w.id, id);
    });

    test('an unconnected requester is Forbidden', () async {
      final id = await h.seedWorkout(userId: ownerId);
      await expectLater(
        h.db.getTargetWorkout(requesterId: strangerId, targetUserId: ownerId, workoutId: id, imageUrl: imageUrl),
        throwsA(isA<Forbidden>()),
      );
    });

    test('a requester whose connection is merely pending is Forbidden', () async {
      final owner = await h.seedProfile();
      final asker = await h.seedProfile();
      final id = await h.seedWorkout(userId: owner);
      await h.seedConnection(initiator: asker, target: owner, role: 'COACH', status: 'pending');

      await expectLater(
        h.db.getTargetWorkout(requesterId: asker, targetUserId: owner, workoutId: id, imageUrl: imageUrl),
        throwsA(isA<Forbidden>()),
      );
    });

    test('a connected requester gets NotFound for a missing workout', () async {
      await expectLater(
        h.db.getTargetWorkout(
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
      final w1 = await h.seedWorkout(userId: listOwnerId, name: 'W1');
      final w2 = await h.seedWorkout(userId: listOwnerId, name: 'W2');

      final page1 = await h.db.getWorkouts(
        userId: listOwnerId,
        targetUserId: listOwnerId,
        limit: 1,
        imageUrl: imageUrl,
      );
      expect(page1.items, hasLength(1));
      expect(page1.hasMore, isTrue);
      expect(page1.items.single.id, w2); // uuidv7 → newest first

      final page2 = await h.db.getWorkouts(
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
      await h.seedWorkout(userId: ownerId);
      final page = await h.db.getWorkouts(userId: peerId, targetUserId: ownerId, limit: 10, imageUrl: imageUrl);
      expect(page.items, isNotEmpty);
    });

    test('an unconnected requester is Forbidden', () async {
      await expectLater(
        h.db.getWorkouts(userId: strangerId, targetUserId: ownerId, limit: 10, imageUrl: imageUrl),
        throwsA(isA<Forbidden>()),
      );
    });

    // The gate used to check only that a connection row existed with the right
    // role, so an unanswered request — or one that had been declined, severed or
    // blocked — read as permission to browse someone's whole history.
    for (final status in ['pending', 'declined', 'severed', 'blocked', 'paused']) {
      test('a requester whose connection is $status is Forbidden', () async {
        final owner = await h.seedProfile();
        final asker = await h.seedProfile();
        await h.seedWorkout(userId: owner);
        await h.seedConnection(initiator: asker, target: owner, role: 'COACH', status: status);

        await expectLater(
          h.db.getWorkouts(userId: asker, targetUserId: owner, limit: 10, imageUrl: imageUrl),
          throwsA(isA<Forbidden>()),
        );
      });
    }
  });

  group('updateWorkout', () {
    test('replaces the times, name, and exercises', () async {
      final exA = h.uniqueName('Ex');
      await h.seedGlobalExercise(name: exA);
      final id = (await h.db.createWorkout(
        userId: ownerId,
        body: req(ownerId, name: 'V1', start: DateTime.utc(2026, 7, 25, 8), exerciseName: exA),
        imageUrl: imageUrl,
      )).id;

      final exB = h.uniqueName('Ex');
      await h.seedGlobalExercise(name: exB);
      final updated = await h.db.updateWorkout(
        userId: ownerId,
        workoutId: id,
        body: req(
          ownerId,
          name: 'V2',
          start: DateTime.utc(2026, 7, 25, 9),
          end: DateTime.utc(2026, 7, 25, 10),
          exerciseName: exB,
        ),
        imageUrl: imageUrl,
      );

      expect(updated.name, 'V2');
      expect(updated.start.toUtc(), DateTime.utc(2026, 7, 25, 9));
      expect(updated.length, 1);
      expect(updated.first.exercise.name, exB); // A replaced by B
    });

    test('updating a workout you do not own throws NotFound', () async {
      final id = await h.seedWorkout(userId: ownerId);
      await expectLater(
        h.db.updateWorkout(
          userId: strangerId,
          workoutId: id,
          body: req(strangerId, name: 'hijack', start: DateTime.utc(2026, 7, 25, 9), exerciseName: 'nonexistent'),
          imageUrl: imageUrl,
        ),
        throwsA(isA<NotFound>()),
      );
    });
  });

  group('energy fields', () {
    test('calories, met, and set timing round-trip through create and read', () async {
      final exName = h.uniqueName('Ex');
      await h.seedGlobalExercise(name: exName);

      final created = await h.db.createWorkout(
        userId: ownerId,
        body: WorkoutRequest(
          userId: ownerId,
          body: {
            'name': 'Energy workout',
            'start': '2026-08-08T10:00:00Z',
            'end': '2026-08-08T11:00:00Z',
            'calories': 512,
            'exercises': [
              {
                'exercise': exName,
                'order': 0,
                'met': 5.5,
                'sets': [
                  {
                    'weight': 100,
                    'reps': 5,
                    'completed': true,
                    'started_at': '2026-08-08T10:00:00Z',
                    'completed_at': '2026-08-08T10:01:30Z',
                  },
                ],
              },
            ],
          },
        ),
        imageUrl: imageUrl,
      );

      expect(created.calories, 512.0);
      expect(created.first.met, 5.5);
      expect(created.first.first.completedAt?.toUtc(), DateTime.utc(2026, 8, 8, 10, 1, 30));

      final read = await h.db.getWorkout(userId: ownerId, workoutId: created.id, imageUrl: imageUrl);
      expect(read.calories, 512.0);
      expect(read.first.met, 5.5);
      expect(read.first.first.completedAt?.toUtc(), DateTime.utc(2026, 8, 8, 10, 1, 30));
    });

    test('a per-exercise note round-trips through create, read, and a full-replace update', () async {
      final exName = h.uniqueName('Ex');
      await h.seedGlobalExercise(name: exName);

      WorkoutRequest withNote(String note) => WorkoutRequest(
        userId: ownerId,
        body: {
          'name': 'Noted workout',
          'start': '2026-08-08T10:00:00Z',
          'end': '2026-08-08T11:00:00Z',
          'exercises': [
            {'exercise': exName, 'order': 0, 'note': note, 'sets': <Map>[]},
          ],
        },
      );

      final created = await h.db.createWorkout(
        userId: ownerId,
        body: withNote('do one hand at a time'),
        imageUrl: imageUrl,
      );
      expect(created.first.note, 'do one hand at a time');

      final read = await h.db.getWorkout(userId: ownerId, workoutId: created.id, imageUrl: imageUrl);
      expect(read.first.note, 'do one hand at a time');

      // updateWorkout deletes and re-inserts workout_exercises; the note must survive
      final updated = await h.db.updateWorkout(
        userId: ownerId,
        workoutId: created.id,
        body: withNote('pause at the bottom'),
        imageUrl: imageUrl,
      );
      expect(updated.first.note, 'pause at the bottom');
    });

    test('a calories-only patch sets calories and leaves the rest unchanged', () async {
      final id = await h.seedWorkout(userId: ownerId);

      final updated = await h.db.patchWorkout(userId: ownerId, workoutId: id, calories: 300.5, imageUrl: imageUrl);

      expect(updated.calories, 300.5);
      expect(updated.name, 'Original');
      expect(updated.start.toUtc(), DateTime.utc(2026, 7, 20, 18)); // original
    });

    test('a name-only patch preserves previously set calories', () async {
      final id = await h.seedWorkout(userId: ownerId);
      await h.db.patchWorkout(userId: ownerId, workoutId: id, calories: 300.5, imageUrl: imageUrl);

      final updated = await h.db.patchWorkout(userId: ownerId, workoutId: id, name: 'Renamed', imageUrl: imageUrl);

      expect(updated.calories, 300.5);
      expect(updated.name, 'Renamed');
    });
  });

  group('deleteWorkout', () {
    test('the owner deletes their workout', () async {
      final id = await h.seedWorkout(userId: ownerId);
      await h.db.deleteWorkout(userId: ownerId, workoutId: id);
      await expectLater(
        h.db.getWorkout(userId: ownerId, workoutId: id, imageUrl: imageUrl),
        throwsA(isA<NotFound>()),
      );
    });

    test('deleting a workout you do not own is a no-op', () async {
      final id = await h.seedWorkout(userId: ownerId);
      await h.db.deleteWorkout(userId: strangerId, workoutId: id);
      final w = await h.db.getWorkout(userId: ownerId, workoutId: id, imageUrl: imageUrl);
      expect(w.id, id); // still there
    });
  });

  group('patchWorkout', () {
    test('updates only the provided fields and preserves exercises', () async {
      final id = await h.seedWorkout(userId: ownerId, withExercise: true);
      final newStart = DateTime.utc(2026, 7, 20, 17, 30);
      final newEnd = DateTime.utc(2026, 7, 20, 18, 45);

      final updated = await h.db.patchWorkout(
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
      final id = await h.seedWorkout(userId: ownerId);

      final updated = await h.db.patchWorkout(userId: ownerId, workoutId: id, name: 'Renamed only', imageUrl: imageUrl);

      expect(updated.name, 'Renamed only');
      expect(updated.start.toUtc(), DateTime.utc(2026, 7, 20, 18)); // original
      expect(updated.end?.toUtc(), DateTime.utc(2026, 7, 20, 19)); // original
    });

    test('does not touch a workout owned by someone else', () async {
      final id = await h.seedWorkout(userId: ownerId);
      await expectLater(
        h.db.patchWorkout(userId: strangerId, workoutId: id, name: 'Hijacked', imageUrl: imageUrl),
        throwsA(isA<NotFound>()),
      );
      final owned = await h.db.getWorkout(userId: ownerId, workoutId: id, imageUrl: imageUrl);
      expect(owned.name, 'Original');
    });
  });
}

class _Harness extends DatabaseTestBase;
