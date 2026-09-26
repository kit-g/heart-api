@Tags(['db'])
library;

import 'package:heart/models/errors.dart';
import 'package:heart/models/imports.dart';
import 'package:heart/models/workouts.dart';
import 'package:heart_models/heart_models.dart' show MeasurementUnit;
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

  group('case-insensitive name resolution', () {
    // the DB's own notion of exercise identity is (user_id, lower(name)) —
    // resolution must agree with it, or a case-variant spelling either forks
    // a duplicate custom or crashes the insert on the unique index

    test('a case-variant of a global resolves to it instead of forking a custom', () async {
      final shouter = await freshProfile();
      final report = await h.db.importWorkouts(
        userId: shouter,
        batch: WorkoutImport.fromStrongCsv(
          'Date,Workout Name,Duration,Exercise Name,Set Order,Weight,Reps\n'
          '2023-03-01 09:00:00,Push,30m,${benchName.toUpperCase()},1,60,8\n',
        ),
      );

      expect(report.exercisesMatched, 1);
      expect(report.exercisesCreated, isEmpty);
      expect(report.setsCreated, 1);

      final owner = await h.exec(
        'SELECT DISTINCT e.user_id FROM exercises e '
        'JOIN workout_exercises we ON we.exercise_id = e.id '
        'JOIN workouts w ON w.id = we.workout_id '
        'WHERE w.user_id = @id',
        {'id': shouter},
      );
      expect(owner.single.toColumnMap()['user_id'], isNull);
    });

    test(
      'a case-variant of an existing custom resolves to it instead of tripping unique (user_id, lower(name))',
      () async {
        final shouter = await freshProfile();
        final name = h.uniqueName('Mystery Move');
        await h.db.importWorkouts(
          userId: shouter,
          batch: WorkoutImport.fromStrongCsv(
            'Date,Workout Name,Duration,Exercise Name,Set Order,Weight,Reps\n'
            '2023-03-01 09:00:00,Day One,30m,$name,1,60,8\n',
          ),
        );

        final again = await h.db.importWorkouts(
          userId: shouter,
          batch: WorkoutImport.fromStrongCsv(
            'Date,Workout Name,Duration,Exercise Name,Set Order,Weight,Reps\n'
            '2023-03-02 09:00:00,Day Two,30m,${name.toLowerCase()},1,62,8\n',
          ),
        );
        expect(again.exercisesMatched, 1);
        expect(again.exercisesCreated, isEmpty);

        final customs = await h.exec('SELECT name FROM exercises WHERE user_id = @id', {'id': shouter});
        expect(customs.map((r) => r.toColumnMap()['name']), [name]);
      },
    );

    test('two case-variant spellings in one export fold into a single created custom', () async {
      final shouter = await freshProfile();
      final name = h.uniqueName('Mystery Move');
      final report = await h.db.importWorkouts(
        userId: shouter,
        batch: WorkoutImport.fromStrongCsv(
          'Date,Workout Name,Duration,Exercise Name,Set Order,Weight,Reps\n'
          '2023-03-01 09:00:00,Day One,30m,$name,1,60,8\n'
          '2023-03-01 09:00:00,Day One,30m,${name.toLowerCase()},1,62,8\n',
        ),
      );

      expect(report.exercisesCreated, hasLength(1));
      expect(report.exercisesSkipped, isEmpty);
      expect(report.setsCreated, 2);

      final customs = await h.exec('SELECT count(*)::int AS n FROM exercises WHERE user_id = @id', {'id': shouter});
      expect(customs.single.toColumnMap()['n'], 1);
    });

    test('the preview reports a case-variant as matched, under its incoming spelling', () async {
      final shouter = await freshProfile();
      final preview = await h.db.previewImport(
        userId: shouter,
        batch: WorkoutImport.fromStrongCsv(
          'Date,Workout Name,Duration,Exercise Name,Set Order,Weight,Reps\n'
          '2023-03-01 09:00:00,Push,30m,${benchName.toUpperCase()},1,60,8\n',
        ),
      );
      expect(preview.exercisesMatched, 1);
      expect(preview.exercisesUnmatched, isEmpty);
    });
  });

  group('set type, RPE, notes, rest timers and re-import enrichment', () {
    late String dip; // a global the exports below resolve to

    const header =
        'Date,Workout Name,Duration,Exercise Name,Set Order,Weight,Reps,Distance,Seconds,Notes,Workout Notes,RPE\n';

    // the same session exported with everything switched on ...
    String rich() =>
        '$header'
        '2025-07-14 20:44:18,Evening,1h,$dip,W,20,10,0,0,slow eccentric,deload week,\n'
        '2025-07-14 20:44:18,Evening,1h,$dip,Rest Timer,0,0,0,90,,,\n'
        '2025-07-14 20:44:18,Evening,1h,$dip,1,45,8,0,0,,,8.5\n'
        '2025-07-14 20:44:18,Evening,1h,$dip,Rest Timer,0,0,0,120,,,\n'
        '2025-07-14 20:44:18,Evening,1h,$dip,2,50,6,0,0,,,9\n'
        '2025-07-14 20:44:18,Evening,1h,$dip,Rest Timer,0,0,0,120,,,\n';

    // ... and with notes, RPE and rest timers left out
    String bare() =>
        '$header'
        '2025-07-14 20:44:18,Evening,1h,$dip,W,20,10,0,0,,,\n'
        '2025-07-14 20:44:18,Evening,1h,$dip,1,45,8,0,0,,,\n'
        '2025-07-14 20:44:18,Evening,1h,$dip,2,50,6,0,0,,,\n';

    Future<WorkoutImportReport> import(String owner, String csv, {List<String>? createCustom}) =>
        h.db.importWorkouts(userId: owner, batch: WorkoutImport.fromStrongCsv(csv), createCustom: createCustom);

    Future<List<Map<String, dynamic>>> sets(String owner) async {
      final rows = await h.exec(
        'SELECT es.set_order, es.weight::float8 AS weight, _set_type_name(es.set_type) AS set_type, es.rpe::float8 AS rpe '
        'FROM exercise_sets es '
        'JOIN workout_exercises we ON we.id = es.workout_exercise_id '
        'JOIN workouts w ON w.id = we.workout_id WHERE w.user_id = @id ORDER BY es.set_order',
        {'id': owner},
      );
      return [for (final r in rows) r.toColumnMap()];
    }

    Future<Map<String, dynamic>> notes(String owner) async {
      final rows = await h.exec(
        'SELECT w.note AS workout_note, we.note AS exercise_note FROM workouts w '
        'JOIN workout_exercises we ON we.workout_id = w.id WHERE w.user_id = @id',
        {'id': owner},
      );
      return rows.single.toColumnMap();
    }

    Future<int?> restTimer(String owner) async {
      final rows = await h.exec(
        'SELECT ep.rest_timer FROM exercise_preferences ep JOIN exercises e ON e.id = ep.exercise_id '
        'WHERE ep.user_id = @id AND e.name = @n',
        {'id': owner, 'n': dip},
      );
      return rows.isEmpty ? null : rows.single.toColumnMap()['rest_timer'] as int?;
    }

    setUpAll(() async {
      dip = h.uniqueName('Chest Dip');
      await h.seedGlobalExercise(name: dip);
    });

    test('a rich export lands set types, RPE, notes and the rest timer', () async {
      final owner = await freshProfile();
      final report = await import(owner, rich());

      expect(report.workoutsCreated, 1);
      expect(report.restTimersSet, 1);
      expect((await sets(owner)).map((s) => (s['set_type'], s['rpe'])), [
        ('warmup', null),
        ('normal', 8.5),
        ('normal', 9.0),
      ]);
      expect(await notes(owner), {'workout_note': 'deload week', 'exercise_note': 'slow eccentric'});
      // the timer after the warm-up is Strong's warm-up timer, not this one
      expect(await restTimer(owner), 120);
    });

    test('a richer re-export fills the gaps a bare one left, and says so', () async {
      final owner = await freshProfile();
      await import(owner, bare());

      final report = await import(owner, rich());
      expect(report.workoutsCreated, 0);
      expect(report.workoutsEnriched, 1);
      // the W set already had its type from the bare export; the other two gain RPE
      expect(report.setsEnriched, 2);
      expect(report.workoutsSkipped, 0);
      expect(report.restTimersSet, 1);

      expect((await sets(owner)).map((s) => s['rpe']), [null, 8.5, 9.0]);
      expect(await notes(owner), {'workout_note': 'deload week', 'exercise_note': 'slow eccentric'});
      final count = await h.exec('SELECT count(*)::int AS n FROM workouts WHERE user_id = @id', {'id': owner});
      expect(count.single.toColumnMap()['n'], 1);
    });

    test('a workout imported before any of this existed is filled in by the same file', () async {
      final owner = await freshProfile();
      await import(owner, rich());
      // what an import from before these columns looks like
      await h.exec(
        'UPDATE exercise_sets SET set_type = NULL, rpe = NULL WHERE workout_exercise_id IN ('
        '  SELECT we.id FROM workout_exercises we JOIN workouts w ON w.id = we.workout_id WHERE w.user_id = @id)',
        {'id': owner},
      );
      await h.exec(
        'UPDATE workout_exercises SET note = NULL WHERE workout_id IN (SELECT id FROM workouts WHERE user_id = @id)',
        {'id': owner},
      );
      await h.exec('UPDATE workouts SET note = NULL WHERE user_id = @id', {'id': owner});

      final report = await import(owner, rich());
      expect(report.workoutsEnriched, 1);
      expect(report.setsEnriched, 3);
      expect((await sets(owner)).map((s) => s['set_type']), ['warmup', 'normal', 'normal']);
      expect(await notes(owner), {'workout_note': 'deload week', 'exercise_note': 'slow eccentric'});
    });

    test('a poorer re-export takes nothing away', () async {
      final owner = await freshProfile();
      await import(owner, rich());
      final setsBefore = await sets(owner);
      final notesBefore = await notes(owner);

      final report = await import(owner, bare());
      expect(report.workoutsEnriched, 0);
      expect(report.setsEnriched, 0);
      expect(report.workoutsSkipped, 1);
      expect(await sets(owner), setsBefore);
      expect(await notes(owner), notesBefore);
      expect(await restTimer(owner), 120);
    });

    test('a value already there wins over a different incoming one', () async {
      final owner = await freshProfile();
      await import(owner, bare());
      await h.exec(
        "UPDATE workout_exercises SET note = 'my own note' WHERE workout_id IN (SELECT id FROM workouts WHERE user_id = @id)",
        {'id': owner},
      );
      await h.exec(
        'UPDATE exercise_sets SET rpe = 7 WHERE set_order = 1 AND workout_exercise_id IN ('
        '  SELECT we.id FROM workout_exercises we JOIN workouts w ON w.id = we.workout_id WHERE w.user_id = @id)',
        {'id': owner},
      );

      await import(owner, rich());
      expect((await notes(owner))['exercise_note'], 'my own note');
      expect((await sets(owner)).map((s) => s['rpe']), [null, 7.0, 9.0]);
    });

    test('a set edited since the import is not enriched; its neighbours are', () async {
      final owner = await freshProfile();
      await import(owner, bare());
      await h.exec(
        'UPDATE exercise_sets SET weight = 47 WHERE set_order = 1 AND workout_exercise_id IN ('
        '  SELECT we.id FROM workout_exercises we JOIN workouts w ON w.id = we.workout_id WHERE w.user_id = @id)',
        {'id': owner},
      );

      final report = await import(owner, rich());
      expect(report.setsEnriched, 1);
      expect((await sets(owner)).map((s) => (s['weight'], s['rpe'])), [(20.0, null), (47.0, null), (50.0, 9.0)]);
    });

    test('a deleted set does not hand its RPE to the set that moved into its place', () async {
      final owner = await freshProfile();
      await import(owner, bare());
      // the app renumbers on delete: 45x8 goes, 50x6 becomes set_order 1
      await h.exec(
        'DELETE FROM exercise_sets WHERE set_order = 1 AND workout_exercise_id IN ('
        '  SELECT we.id FROM workout_exercises we JOIN workouts w ON w.id = we.workout_id WHERE w.user_id = @id)',
        {'id': owner},
      );
      await h.exec(
        'UPDATE exercise_sets SET set_order = 1 WHERE set_order = 2 AND workout_exercise_id IN ('
        '  SELECT we.id FROM workout_exercises we JOIN workouts w ON w.id = we.workout_id WHERE w.user_id = @id)',
        {'id': owner},
      );

      await import(owner, rich());
      expect((await sets(owner)).map((s) => (s['weight'], s['rpe'])), [(20.0, null), (50.0, null)]);
    });

    test('the preview reports exactly what the commit then does, writing nothing', () async {
      final owner = await freshProfile();
      await import(owner, bare());
      final setsBefore = await sets(owner);
      final notesBefore = await notes(owner);

      final preview = await h.db.previewImport(userId: owner, batch: WorkoutImport.fromStrongCsv(rich()));
      expect(await sets(owner), setsBefore);
      expect(await notes(owner), notesBefore);
      expect(await restTimer(owner), isNull);

      final report = await import(owner, rich());
      expect(
        (preview.workoutsEnriched, preview.setsEnriched, preview.restTimersSet),
        (report.workoutsEnriched, report.setsEnriched, report.restTimersSet),
      );
      expect(preview.workoutsEnriched, 1);
    });

    test('a rest timer the user already set is kept; a preference without one gains it', () async {
      final keeps = await freshProfile();
      await h.exec(
        'INSERT INTO exercise_preferences (user_id, exercise_id, rest_timer) '
        'SELECT @id, id, 60 FROM exercises WHERE name = @n',
        {'id': keeps, 'n': dip},
      );
      expect((await import(keeps, rich())).restTimersSet, 0);
      expect(await restTimer(keeps), 60);

      final gains = await freshProfile();
      await h.exec(
        "INSERT INTO exercise_preferences (user_id, exercise_id, unit_system) SELECT @id, id, 'imperial' FROM exercises WHERE name = @n",
        {'id': gains, 'n': dip},
      );
      expect((await import(gains, rich())).restTimersSet, 1);
      expect(await restTimer(gains), 120);
    });

    test('a declined custom exercise gets no rest timer', () async {
      final owner = await freshProfile();
      final unknown = h.uniqueName('Sled Push');
      final report = await import(owner, rich().replaceAll(dip, unknown), createCustom: const []);
      expect(report.restTimersSet, 0);
      final prefs = await h.exec('SELECT count(*)::int AS n FROM exercise_preferences WHERE user_id = @id', {
        'id': owner,
      });
      expect(prefs.single.toColumnMap()['n'], 0);
    });
  });

  group('re-import, the nasty cases', () {
    late String dip;
    late String row; // a second global, for two-exercise sessions

    const header =
        'Date,Workout Name,Duration,Exercise Name,Set Order,Weight,Reps,Distance,Seconds,Notes,Workout Notes,RPE\n';

    /// One session of [dip]: a warm-up and two working sets, with RPE, notes
    /// and rest timers when [rich].
    String session(String date, {bool rich = true, String? exercise}) {
      final e = exercise ?? dip;
      return rich
          ? '$date,Evening,1h,$e,W,20,10,0,0,slow eccentric,deload week,\n'
                '$date,Evening,1h,$e,Rest Timer,0,0,0,90,,,\n'
                '$date,Evening,1h,$e,1,45,8,0,0,,,8.5\n'
                '$date,Evening,1h,$e,Rest Timer,0,0,0,120,,,\n'
                '$date,Evening,1h,$e,2,50,6,0,0,,,9\n'
          : '$date,Evening,1h,$e,W,20,10,0,0,,,\n'
                '$date,Evening,1h,$e,1,45,8,0,0,,,\n'
                '$date,Evening,1h,$e,2,50,6,0,0,,,\n';
    }

    const july = '2025-07-14 20:44:18';
    const june = '2025-06-10 19:00:00';
    const may = '2025-05-05 18:30:00';

    Future<WorkoutImportReport> import(
      String owner,
      String csv, {
      List<String>? createCustom,
      Duration utcOffset = Duration.zero,
      MeasurementUnit unit = MeasurementUnit.metric,
    }) => h.db.importWorkouts(
      userId: owner,
      batch: WorkoutImport.fromStrongCsv(csv, utcOffset: utcOffset, unit: unit),
      createCustom: createCustom,
    );

    Future<List<Map<String, dynamic>>> sets(String owner) async {
      final rows = await h.exec(
        'SELECT es.id::text AS id, we.exercise_order, es.set_order, es.weight::float8 AS weight, '
        '       _set_type_name(es.set_type) AS set_type, es.rpe::float8 AS rpe '
        'FROM exercise_sets es JOIN workout_exercises we ON we.id = es.workout_exercise_id '
        'JOIN workouts w ON w.id = we.workout_id WHERE w.user_id = @id '
        'ORDER BY w.started_at, we.exercise_order, es.set_order',
        {'id': owner},
      );
      return [for (final r in rows) r.toColumnMap()];
    }

    Future<int> workoutCount(String owner) async {
      final rows = await h.exec('SELECT count(*)::int AS n FROM workouts WHERE user_id = @id', {'id': owner});
      return rows.single.toColumnMap()['n'] as int;
    }

    Future<void> sql(String owner, String statement) => h.exec(statement, {'id': owner});

    setUpAll(() async {
      dip = h.uniqueName('Chest Dip');
      row = h.uniqueName('Seated Row');
      await h.seedGlobalExercise(name: dip);
      await h.seedGlobalExercise(name: row);
    });

    test('a mixed batch: new, enrichable and already complete workouts each counted once', () async {
      final owner = await freshProfile();
      await import(owner, '$header${session(july, rich: false)}${session(june)}');

      final report = await import(owner, '$header${session(july)}${session(june)}${session(may)}');
      expect(report.workoutsFound, 3);
      expect(report.workoutsCreated, 1); // May
      expect(report.workoutsEnriched, 1); // July
      expect(report.workoutsSkipped, 1); // June, nothing to fill
      expect(report.setsEnriched, 2);
      expect(report.setsCreated, 3);
      expect(await workoutCount(owner), 3);
    });

    test('the richer export run twice enriches once, then skips', () async {
      final owner = await freshProfile();
      await import(owner, '$header${session(july, rich: false)}');
      expect((await import(owner, '$header${session(july)}')).workoutsEnriched, 1);

      final again = await import(owner, '$header${session(july)}');
      expect(again.workoutsEnriched, 0);
      expect(again.setsEnriched, 0);
      expect(again.restTimersSet, 0);
      expect(again.workoutsSkipped, 1);
    });

    test('a re-export from another time zone lands on the same workout, which keeps its time', () async {
      final owner = await freshProfile();
      await import(owner, '$header${session(july, rich: false)}');
      final before = await h.exec('SELECT started_at FROM workouts WHERE user_id = @id', {'id': owner});

      final report = await import(owner, '$header${session(july)}', utcOffset: const Duration(hours: 2));
      expect(report.workoutsCreated, 0);
      expect(report.workoutsEnriched, 1);
      expect(await workoutCount(owner), 1);
      final after = await h.exec('SELECT started_at FROM workouts WHERE user_id = @id', {'id': owner});
      expect(after.single.toColumnMap(), before.single.toColumnMap());
    });

    test('a re-export spelling the exercise in another case still matches', () async {
      final owner = await freshProfile();
      await import(owner, '$header${session(july, rich: false)}');
      final report = await import(owner, '$header${session(july, exercise: dip.toLowerCase())}');
      expect(report.setsEnriched, 2);
      expect((await sets(owner)).map((s) => s['rpe']), [null, 8.5, 9.0]);
    });

    test('exercises reordered in the app take nothing from each other', () async {
      final owner = await freshProfile();
      await import(owner, '$header${session(july, rich: false)}${session(july, rich: false, exercise: row)}');
      // swap the two exercises' positions, as a drag in the app would
      await sql(
        owner,
        'UPDATE workout_exercises SET exercise_order = 1 - exercise_order '
        'WHERE workout_id IN (SELECT id FROM workouts WHERE user_id = @id)',
      );

      final report = await import(owner, '$header${session(july)}${session(july, exercise: row)}');
      expect(report.setsEnriched, 0);
      expect((await sets(owner)).every((s) => s['rpe'] == null), isTrue);
      final notes = await h.exec(
        'SELECT count(*)::int AS n FROM workout_exercises we JOIN workouts w ON w.id = we.workout_id '
        'WHERE w.user_id = @id AND we.note IS NOT NULL',
        {'id': owner},
      );
      expect(notes.single.toColumnMap()['n'], 0);
    });

    test('a set the user appended is left alone; the original ones are enriched', () async {
      final owner = await freshProfile();
      await import(owner, '$header${session(july, rich: false)}');
      await sql(
        owner,
        'INSERT INTO exercise_sets (workout_exercise_id, set_order, weight, reps, completed) '
        'SELECT we.id, 3, 55, 4, true FROM workout_exercises we JOIN workouts w ON w.id = we.workout_id WHERE w.user_id = @id',
      );

      final report = await import(owner, '$header${session(july)}');
      expect(report.setsEnriched, 2);
      expect((await sets(owner)).map((s) => (s['weight'], s['rpe'])), [
        (20.0, null),
        (45.0, 8.5),
        (50.0, 9.0),
        (55.0, null),
      ]);
    });

    test('an edit from today\'s app between the two imports keeps the workout enrichable', () async {
      final owner = await freshProfile();
      await import(owner, '$header${session(july, rich: false)}');
      final idsBefore = [for (final s in await sets(owner)) s['id']];

      // what the current app sends: the whole body, ids round-tripped, no set_type/rpe
      final workoutId =
          (await h.exec('SELECT id::text AS id FROM workouts WHERE user_id = @id', {
                'id': owner,
              })).single.toColumnMap()['id']
              as String;
      final stored = await h.db.getWorkout(userId: owner, workoutId: workoutId, imageUrl: (k) => k);
      await h.db.updateWorkout(
        userId: owner,
        workoutId: workoutId,
        body: WorkoutRequest(userId: owner, body: stored.toMap()),
        imageUrl: (k) => k,
      );
      expect([for (final s in await sets(owner)) s['id']], idsBefore);
      expect((await sets(owner)).map((s) => s['set_type']), ['warmup', 'normal', 'normal']);

      final report = await import(owner, '$header${session(july)}');
      expect(report.setsEnriched, 2);
      expect((await sets(owner)).map((s) => s['rpe']), [null, 8.5, 9.0]);
    });

    test('a workout the user deleted comes back from a re-import', () async {
      // the import identity goes with the row, so the file is its only record
      final owner = await freshProfile();
      await import(owner, '$header${session(july, rich: false)}');
      await sql(owner, 'DELETE FROM workouts WHERE user_id = @id');

      final report = await import(owner, '$header${session(july)}');
      expect(report.workoutsCreated, 1);
      expect(report.workoutsEnriched, 0);
      expect((await sets(owner)).map((s) => s['rpe']), [null, 8.5, 9.0]);
    });

    test('someone else importing the same file never touches your workouts', () async {
      final mine = await freshProfile();
      final theirs = await freshProfile();
      await import(mine, '$header${session(july, rich: false)}');

      final report = await import(theirs, '$header${session(july)}');
      expect(report.workoutsCreated, 1);
      expect(report.workoutsEnriched, 0);
      expect((await sets(mine)).every((s) => s['rpe'] == null), isTrue);
      expect(await workoutCount(mine), 1);
    });

    test('an exercise declined at first is not added later; the rest of the workout is enriched', () async {
      final owner = await freshProfile();
      final sled = h.uniqueName('Sled Push');
      await import(
        owner,
        '$header${session(july, rich: false)}${session(july, rich: false, exercise: sled)}',
        createCustom: const [],
      );
      expect((await sets(owner)), hasLength(3));

      final report = await import(
        owner,
        '$header${session(july)}${session(july, exercise: sled)}',
        createCustom: [sled],
      );
      expect(report.workoutsCreated, 0);
      expect(report.workoutsEnriched, 1);
      expect(report.setsEnriched, 2);
      expect(report.exercisesCreated, [sled]);
      // enrichment never changes structure: the sled's sets stay out
      expect(await sets(owner), hasLength(3));
    });

    test('the same unit on both exports matches after conversion', () async {
      final owner = await freshProfile();
      final lbs = header.replaceFirst('Weight,', 'Weight,Weight Unit,');
      String inLbs(String rows) =>
          rows.replaceAllMapped(RegExp(r',(W|1|2|Rest Timer),(\d+),'), (m) => ',${m[1]},${m[2]},lbs,');
      await import(owner, '$lbs${inLbs(session(july, rich: false))}');

      final report = await import(owner, '$lbs${inLbs(session(july))}');
      expect(report.setsEnriched, 2);
    });

    test('a re-export in the other unit matches nothing and changes nothing', () async {
      // 45 kg exports as 99.21 lb, which converts back to 45.0014 kg: not the
      // same set by its numbers, so it is left alone rather than guessed at
      final owner = await freshProfile();
      await import(owner, '$header${session(july, rich: false)}');
      final lbs = header.replaceFirst('Weight,', 'Weight,Weight Unit,');
      final rich =
          '$july,Evening,1h,$dip,W,44.09,lbs,10,0,0,slow eccentric,deload week,\n'
          '$july,Evening,1h,$dip,1,99.21,lbs,8,0,0,,,8.5\n'
          '$july,Evening,1h,$dip,2,110.23,lbs,6,0,0,,,9\n';

      final report = await import(owner, '$lbs$rich');
      expect(report.setsEnriched, 0);
      expect((await sets(owner)).every((s) => s['rpe'] == null), isTrue);
      // the workout note has no numbers to disagree on, so it still lands
      expect(report.workoutsEnriched, 1);
    });

    test('the preview counts rest timers for names it cannot match yet', () async {
      final owner = await freshProfile();
      final sled = h.uniqueName('Sled Push');
      final preview = await h.db.previewImport(
        userId: owner,
        batch: WorkoutImport.fromStrongCsv('$header${session(july)}${session(july, exercise: sled)}'),
      );
      expect(preview.restTimersSet, 2);
      expect(preview.exercisesUnmatched.map((e) => e.name), [sled]);
    });
  });

  test('an account at the custom-exercises ceiling gets a 400 instead of import-created customs', () async {
    final collector = await freshProfile();
    await h.exec(
      'INSERT INTO exercises (name, category, target, user_id) '
      "SELECT 'cap test ' || @id || ' ' || n, 'Barbell', 'Other', @id FROM generate_series(1, 2000) n",
      {'id': collector},
    );

    // csv() carries two names this user has never seen — creating them would
    // cross the 2000-customs ceiling, so the whole import is refused
    await expectLater(
      h.db.importWorkouts(userId: collector, batch: WorkoutImport.fromStrongCsv(csv())),
      throwsA(isA<BadRequest>()),
    );
    final count = await h.exec(
      'SELECT count(*)::int AS n FROM workouts WHERE user_id = @id',
      {'id': collector},
    );
    expect(count.first.toColumnMap()['n'], 0);
  });

  test('an account at the DB-enforced import ceiling gets a 400, not a 500', () async {
    final hoarder = await freshProfile();
    // fill to exactly the cap; the workouts_imported_cap trigger allows this
    await h.exec(
      'INSERT INTO workouts (user_id, started_at, import_id) '
      "SELECT @id, now() - (n || ' hours')::interval, 'strong:' || lpad(to_hex(n), 16, '0') "
      'FROM generate_series(1, 20000) n',
      {'id': hoarder},
    );

    await expectLater(
      h.db.importWorkouts(userId: hoarder, batch: WorkoutImport.fromStrongCsv(csv())),
      throwsA(isA<BadRequest>()),
    );

    // the refused batch wrote nothing — neither workouts nor customs
    final counts = await h.exec(
      'SELECT (SELECT count(*) FROM workouts WHERE user_id = @id)::int AS workouts, '
      '       (SELECT count(*) FROM exercises WHERE user_id = @id)::int AS exercises',
      {'id': hoarder},
    );
    expect(counts.first.toColumnMap(), {'workouts': 20000, 'exercises': 0});

    // drop the bulk rows here (and their archive copies) rather than letting
    // teardown route 20k rows through the delete-archival trigger for keeps
    await h.exec('DELETE FROM workouts WHERE user_id = @id', {'id': hoarder});
    await h.exec('DELETE FROM archive.deleted_workouts WHERE user_id = @id', {'id': hoarder});
  });
}

class _Harness extends DatabaseTestBase;
