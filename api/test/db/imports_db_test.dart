@Tags(['db'])
library;

import 'package:heart/models/imports.dart';
import 'package:test/test.dart';

import 'db_test_utility.dart';

/// Integration coverage of the bulk-import query against live Postgres:
/// exercise resolve-or-create, workout/set insertion, the (user_id, import_id)
/// idempotency that makes re-running an export a no-op, start-time uuid-v7
/// minting, the read-only preview, and the createCustom consent decisions.
///
/// Tagged `db` — skipped by the default `dart test`. Run with:
///   dart test --run-skipped -t db
void main() {
  final h = _Harness();

  late String ownerId;
  late String benchName; // pre-seeded global exercise — must resolve, not copy
  late String customName; // only in the CSV — must be created as the user's own
  late String cardioName; // only in the CSV — category inferred from set shape

  String csv() =>
      'Date,Workout Name,Duration,Exercise Name,Set Order,Weight,Reps,Distance,Seconds\n'
      '2023-01-15 17:35:12,Push Day,1h 10m,$benchName,1,80,5,0,0\n'
      '2023-01-15 17:35:12,Push Day,1h 10m,$benchName,2,85,3,0,0\n'
      '2023-01-15 17:35:12,Push Day,1h 10m,$customName,1,25,12,0,0\n'
      '2023-01-17 08:00:00,Morning Run,45m,$cardioName,1,0,0,5.2,1800\n';

  setUpAll(() async {
    await h.setupDatabase();
    ownerId = await h.seedProfile();
    benchName = h.uniqueName('Bench');
    customName = h.uniqueName('Kit Special Press');
    cardioName = h.uniqueName('Ruck');
    await h.seedGlobalExercise(name: benchName);
  });

  final extraProfiles = <String>[];

  Future<String> freshProfile() async {
    final id = await h.seedProfile();
    extraProfiles.add(id);
    return id;
  }

  tearDownAll(() async {
    // workout_exercises.exercise_id is ON DELETE RESTRICT; drop the imported
    // workouts before the profile cascade tries to take the users' custom
    // exercises with it.
    await h.exec('DELETE FROM workouts WHERE user_id = ANY(@ids)', {
      'ids': [ownerId, ...extraProfiles],
    });
    await h.teardownDatabase();
  });

  test('imports a parsed export end to end', () async {
    final batch = WorkoutImport.fromStrongCsv(csv());
    final report = await h.db.importWorkouts(userId: ownerId, batch: batch);

    expect(report.workoutsFound, 2);
    expect(report.workoutsCreated, 2);
    expect(report.workoutsSkipped, 0);
    expect(report.setsCreated, 4);
    expect(report.exercisesMatched, 1);
    expect(report.exercisesCreated, containsAll([customName, cardioName]));
    expect(report.rowsSkipped, 0);
  });

  test('wrote the workout rows with their import identity and window', () async {
    final rows = await h.exec(
      'SELECT name, started_at, completed_at, import_id FROM workouts WHERE user_id = @id ORDER BY started_at',
      {'id': ownerId},
    );
    expect(rows, hasLength(2));

    final push = rows.first.toColumnMap();
    expect(push['name'], 'Push Day');
    // sha256('2023-01-15 17:35:12|Push Day') — the opaque import identity
    expect(push['import_id'], 'strong:b5f8d5d78f2427ef');
    expect((push['started_at'] as DateTime).toUtc(), DateTime.utc(2023, 1, 15, 17, 35, 12));
    expect((push['completed_at'] as DateTime).toUtc(), DateTime.utc(2023, 1, 15, 18, 45, 12));
  });

  test('resolved the known name to the global exercise instead of copying it', () async {
    final rows = await h.exec(
      'SELECT DISTINCT e.user_id FROM exercises e '
      'JOIN workout_exercises we ON we.exercise_id = e.id '
      'JOIN workouts w ON w.id = we.workout_id '
      'WHERE w.user_id = @id AND e.name = @n',
      {'id': ownerId, 'n': benchName},
    );
    expect(rows, hasLength(1));
    expect(rows.first.toColumnMap()['user_id'], isNull);
  });

  test('created unknown names as the user\'s customs with inferred categories', () async {
    final rows = await h.exec(
      'SELECT name, category, target, user_id FROM exercises WHERE user_id = @id ORDER BY name',
      {'id': ownerId},
    );
    final byName = {for (final r in rows) r.toColumnMap()['name']: r.toColumnMap()};
    expect(byName.keys, containsAll([customName, cardioName]));
    expect(byName[customName]!['category'], 'Weighted Body Weight');
    expect(byName[cardioName]!['category'], 'Cardio');
    expect(byName[customName]!['target'], 'Other');
  });

  test('wrote sets with metric measurements in row order', () async {
    final rows = await h.exec(
      'SELECT es.weight, es.reps, es.duration, es.distance, es.completed, es.set_order FROM exercise_sets es '
      'JOIN workout_exercises we ON we.id = es.workout_exercise_id '
      'JOIN exercises e ON e.id = we.exercise_id '
      'JOIN workouts w ON w.id = we.workout_id '
      'WHERE w.user_id = @id AND e.name = @n ORDER BY es.set_order',
      {'id': ownerId, 'n': benchName},
    );
    expect(rows, hasLength(2));
    final first = rows.first.toColumnMap();
    expect(first['weight'], 80);
    expect(first['reps'], 5);
    expect(first['completed'], isTrue);
    expect(first['set_order'], 0);
    expect(rows.last.toColumnMap()['weight'], 85);
  });

  test('re-running the same export is a no-op, reported as skipped', () async {
    final report = await h.db.importWorkouts(userId: ownerId, batch: WorkoutImport.fromStrongCsv(csv()));

    expect(report.workoutsFound, 2);
    expect(report.workoutsCreated, 0);
    expect(report.workoutsSkipped, 2);
    expect(report.setsCreated, 0);
    // the customs created by the first run now resolve as the user's own
    expect(report.exercisesMatched, 3);
    expect(report.exercisesCreated, isEmpty);

    final count = await h.exec('SELECT count(*) AS n FROM workouts WHERE user_id = @id', {'id': ownerId});
    expect(count.first.toColumnMap()['n'], 2);
  });

  test('a grown export imports only the workouts not already there', () async {
    final grown =
        '${csv()}'
        '2023-01-19 18:00:00,Legs,50m,$benchName,1,120,5,0,0\n';
    final report = await h.db.importWorkouts(userId: ownerId, batch: WorkoutImport.fromStrongCsv(grown));

    expect(report.workoutsFound, 3);
    expect(report.workoutsCreated, 1);
    expect(report.setsCreated, 1);
  });

  test('imported ids are uuid-v7 minted at the workout start, so id-order tracks chronology', () async {
    final backdated = await h.exec(
      'SELECT count(*)::int AS total, '
      '       count(*) FILTER (WHERE uuidv7_extract_timestamp(id) = started_at)::int AS at_start '
      'FROM workouts WHERE user_id = @id AND import_id IS NOT NULL',
      {'id': ownerId},
    );
    final counts = backdated.first.toColumnMap();
    expect(counts['total'], 3);
    expect(counts['at_start'], 3);

    // the children carry the same start-time identity — their ids must not
    // claim the workout's content appeared years after the workout itself
    final children = await h.exec(
      'SELECT count(*)::int AS total, '
      '       count(*) FILTER (WHERE uuidv7_extract_timestamp(we.id) = w.started_at '
      '                          AND uuidv7_extract_timestamp(es.id) = w.started_at)::int AS at_start '
      'FROM exercise_sets es '
      'JOIN workout_exercises we ON we.id = es.workout_exercise_id '
      'JOIN workouts w ON w.id = we.workout_id '
      'WHERE w.user_id = @id AND w.import_id IS NOT NULL',
      {'id': ownerId},
    );
    final childCounts = children.first.toColumnMap();
    expect(childCounts['total'], 5);
    expect(childCounts['at_start'], 5);

    // a workout created through the normal write path (id minted now) must
    // outrank years-old imports in the id-keyset feed, regardless of order
    // of arrival
    final fresh = await h.seedWorkout(userId: ownerId, name: 'Today');
    final feed = await h.exec(
      'SELECT id, started_at FROM workouts WHERE user_id = @id ORDER BY id DESC',
      {'id': ownerId},
    );
    expect(feed.first.toColumnMap()['id'].toString(), fresh);
    final imported = feed.skip(1).map((r) => r.toColumnMap()['started_at'] as DateTime).toList();
    final newestFirst = [...imported]..sort((a, b) => b.compareTo(a));
    expect(imported, orderedEquals(newestFirst));
  });

  group('preview (dryRun)', () {
    test('resolves names and identities without writing anything', () async {
      final previewer = await freshProfile();
      final preview = await h.db.previewImport(userId: previewer, batch: WorkoutImport.fromStrongCsv(csv()));

      expect(preview.workoutsFound, 2);
      expect(preview.workoutsAlreadyImported, 0);
      expect(preview.setsFound, 4);
      expect(preview.exercisesMatched, 1); // the global bench
      // the owner's customs must not leak into another user's resolution
      expect(preview.exercisesUnmatched, [
        (name: customName, sets: 1),
        (name: cardioName, sets: 1),
      ]);

      final written = await h.exec(
        'SELECT (SELECT count(*) FROM workouts WHERE user_id = @id)::int AS workouts, '
        '       (SELECT count(*) FROM exercises WHERE user_id = @id)::int AS exercises',
        {'id': previewer},
      );
      expect(written.first.toColumnMap(), {'workouts': 0, 'exercises': 0});
    });

    test('counts workouts already imported for the same user', () async {
      final preview = await h.db.previewImport(userId: ownerId, batch: WorkoutImport.fromStrongCsv(csv()));

      expect(preview.workoutsAlreadyImported, 2);
      // everything resolves now: the global bench plus the customs the real
      // import created for this user
      expect(preview.exercisesMatched, 3);
      expect(preview.exercisesUnmatched, isEmpty);
    });
  });

  group('createCustom consent', () {
    test('a declined name is not created; its sets are skipped and counted', () async {
      final chooser = await freshProfile();
      final report = await h.db.importWorkouts(
        userId: chooser,
        batch: WorkoutImport.fromStrongCsv(csv()),
        createCustom: [cardioName], // approve the cardio custom, decline the other
      );

      expect(report.workoutsFound, 2);
      expect(report.workoutsCreated, 2);
      expect(report.setsCreated, 3); // bench ×2 + approved cardio ×1
      expect(report.setsSkipped, 1); // the declined custom's set
      expect(report.exercisesCreated, [cardioName]);
      expect(report.exercisesSkipped, [customName]);

      final customs = await h.exec('SELECT name FROM exercises WHERE user_id = @id', {'id': chooser});
      expect(customs.map((r) => r.toColumnMap()['name']), [cardioName]);
    });

    test('a workout left with no exercises is not created, keeping its identity unclaimed', () async {
      final chooser = await freshProfile();
      final declined = await h.db.importWorkouts(
        userId: chooser,
        batch: WorkoutImport.fromStrongCsv(csv()),
        createCustom: [], // decline every unmatched name
      );

      // Push Day survives on the matched bench; Morning Run was only the
      // declined cardio, so it must not become an empty workout
      expect(declined.workoutsCreated, 1);
      expect(declined.setsCreated, 2);
      expect(declined.setsSkipped, 2);
      expect(declined.exercisesCreated, isEmpty);
      expect(declined.exercisesSkipped, [customName, cardioName]);

      final names = await h.exec('SELECT name FROM workouts WHERE user_id = @id', {'id': chooser});
      expect(names.map((r) => r.toColumnMap()['name']), ['Push Day']);

      // recovery: re-importing with consent creates the skipped workout in
      // full, and the duplicate contributes nothing to the skip counts
      final recovered = await h.db.importWorkouts(
        userId: chooser,
        batch: WorkoutImport.fromStrongCsv(csv()),
        createCustom: [cardioName],
      );
      expect(recovered.workoutsCreated, 1);
      expect(recovered.setsCreated, 1);
      expect(recovered.setsSkipped, 0); // the declined set is in a duplicate workout
      expect(recovered.exercisesCreated, [cardioName]);
      expect(recovered.exercisesSkipped, [customName]);
    });

    test('a null decision keeps the legacy behavior: create every unmatched name', () async {
      final chooser = await freshProfile();
      final report = await h.db.importWorkouts(userId: chooser, batch: WorkoutImport.fromStrongCsv(csv()));

      expect(report.workoutsCreated, 2);
      expect(report.setsCreated, 4);
      expect(report.setsSkipped, 0);
      expect(report.exercisesCreated, containsAll([customName, cardioName]));
      expect(report.exercisesSkipped, isEmpty);
    });
  });
}

class _Harness extends DatabaseTestBase;
