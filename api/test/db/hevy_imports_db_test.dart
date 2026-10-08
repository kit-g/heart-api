@Tags(['db'])
library;

import 'package:heart/models/imports.dart';
import 'package:test/test.dart';

import 'db_test_utility.dart';

/// A Hevy batch through the import query: a title the app wrote in another
/// language resolves through import_names to its English one, that English
/// name matches the library by name or alias, a translated title the library
/// lacks becomes one custom under its English name, and the `hevy:` import
/// ids hold under the (user_id, import_id) index so a second run of the same
/// export creates nothing.
///
/// Tagged `db` — skipped by the default `dart test`. Run with:
///   dart test --run-skipped -t db
void main() {
  final h = _Harness();

  late String ownerId;
  late String benchName; // seeded global exercise, matched by name
  late String benchDe; // what the German app writes for it: import_names → benchName
  late String benchAlias; // a name the library lists as its alias
  late String pistolDe; // a translated catalog title the library lacks: import_names → pistolEn
  late String pistolEn;
  late String customName; // only in the CSV, as typed

  // rows from a real Hevy app export (test/fixtures/hevy/app-en.csv), with the
  // exercise titles swapped for this run's unique names
  String csv() =>
      '"title","start_time","end_time","description","exercise_title","superset_id","exercise_notes","set_index","set_type","weight_lbs","reps","distance_km","duration_seconds","rpe"\r\n'
      '"Morning Lift","22 Sep 2026, 06:00","22 Sep 2026, 06:50","exact title+start duplicate of the first Morning Lift","$benchDe",,"",0,"normal",82.67,8,,,\r\n'
      '"Morning Lift","22 Sep 2026, 06:00","22 Sep 2026, 06:45","","$benchAlias",,"",0,"normal",88.18,8,,,\r\n'
      '"09 Same exercise twice (edited)","17 Sep 2026, 18:00","17 Sep 2026, 19:25","edited via PUT","$benchName",,"first squat block, edited",0,"normal",220.46,5,,,\r\n'
      '"09 Same exercise twice (edited)","17 Sep 2026, 18:00","17 Sep 2026, 19:25","edited via PUT","$benchName",,"first squat block, edited",1,"normal",225.97,3,,,\r\n'
      '"09 Same exercise twice (edited)","17 Sep 2026, 18:00","17 Sep 2026, 19:25","edited via PUT","$customName",,"",0,"normal",396.83,10,,,\r\n'
      '"09 Same exercise twice (edited)","17 Sep 2026, 18:00","17 Sep 2026, 19:25","edited via PUT","$pistolDe",,"",0,"normal",,6,,,\r\n'
      '"09 Same exercise twice (edited)","17 Sep 2026, 18:00","17 Sep 2026, 19:25","edited via PUT","$benchName",,"back-off squat block",0,"normal",176.37,10,,,';

  setUpAll(() async {
    await h.setupDatabase();
    ownerId = await h.seedProfile();
    benchName = h.uniqueName('Bench Press (Barbell)');
    benchDe = h.uniqueName('Bankdrücken (Langhantel)');
    benchAlias = h.uniqueName('BP');
    pistolDe = h.uniqueName('Pistol-Squat');
    pistolEn = h.uniqueName('Pistol Squat');
    customName = h.uniqueName('Leg Press');
    final benchId = await h.seedGlobalExercise(name: benchName);
    await h.exec('UPDATE exercises SET aliases = ARRAY[@alias] WHERE id = @id', {'alias': benchAlias, 'id': benchId});
    await h.exec(
      "INSERT INTO import_names (source, title, name) VALUES ('hevy', @benchDe, @benchName), ('hevy', @pistolDe, @pistolEn)",
      {'benchDe': benchDe, 'benchName': benchName, 'pistolDe': pistolDe, 'pistolEn': pistolEn},
    );
  });

  tearDownAll(() async {
    await h.exec('DELETE FROM import_names WHERE title = ANY(@titles)', {
      'titles': [benchDe, pistolDe],
    });
    // workout_exercises.exercise_id is ON DELETE RESTRICT; drop the imported
    // workouts before the profile cascade takes the custom exercises with it
    await h.exec('DELETE FROM workouts WHERE user_id = @id', {'id': ownerId});
    await h.teardownDatabase();
  });

  test('the preview matches the translated title and the alias, and lists the rest as typed', () async {
    final batch = WorkoutImport.fromHevyCsv(csv());
    final preview = await h.db.previewImport(userId: ownerId, batch: batch);

    expect(preview.exercisesMatched, 3);
    expect(preview.exercisesUnmatched.map((e) => e.name), [customName, pistolDe]);
    expect(preview.workoutsAlreadyImported, 0);
  });

  test('imports a Hevy batch: translation and alias resolve, customs land under their English name', () async {
    final batch = WorkoutImport.fromHevyCsv(csv());
    final report = await h.db.importWorkouts(userId: ownerId, batch: batch);

    expect(report.source, 'hevy');
    expect(report.workoutsFound, 3);
    expect(report.workoutsCreated, 3);
    expect(report.setsCreated, 7);
    expect(report.exercisesMatched, 3);
    expect(report.exercisesCreated, [customName, pistolEn]);

    final rows = await h.exec(
      'SELECT w.name, we.exercise_order, e.name AS exercise, count(es.id) AS sets '
      'FROM workouts w '
      'JOIN workout_exercises we ON we.workout_id = w.id '
      'JOIN exercises e ON e.id = we.exercise_id '
      'LEFT JOIN exercise_sets es ON es.workout_exercise_id = we.id '
      'WHERE w.user_id = @id '
      'GROUP BY w.id, w.name, w.completed_at, we.exercise_order, e.name '
      'ORDER BY w.name, w.completed_at, we.exercise_order',
      {'id': ownerId},
    );
    expect(
      [for (final r in rows) (r.toColumnMap()['exercise_order'], r.toColumnMap()['exercise'], r.toColumnMap()['sets'])],
      [
        (0, benchName, 2),
        (1, customName, 1),
        (2, pistolEn, 1),
        (3, benchName, 1),
        (0, benchName, 1),
        (0, benchName, 1),
      ],
    );
  });

  test('a second run of the same export creates nothing and reports the skips', () async {
    final batch = WorkoutImport.fromHevyCsv(csv());
    final again = await h.db.importWorkouts(userId: ownerId, batch: batch);

    expect(again.workoutsFound, 3);
    expect(again.workoutsCreated, 0);
    expect(again.workoutsEnriched, 0);
    expect(again.workoutsSkipped, 3);
    expect(again.setsCreated, 0);
    expect(again.exercisesCreated, isEmpty);

    final count = await h.exec('SELECT count(*) AS n FROM workouts WHERE user_id = @id', {'id': ownerId});
    expect(count.single.toColumnMap()['n'], 3);
  });
}

class _Harness extends DatabaseTestBase;
