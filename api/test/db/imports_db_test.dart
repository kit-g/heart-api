@Tags(['db'])
library;

import 'package:heart/models/imports.dart';
import 'package:test/test.dart';

import 'db_test_utility.dart';

/// Integration coverage of the bulk-import query against live Postgres:
/// exercise resolve-or-create, workout/set insertion, and the
/// (user_id, import_id) idempotency that makes re-running an export a no-op.
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

  tearDownAll(() async {
    // workout_exercises.exercise_id is ON DELETE RESTRICT; drop the imported
    // workouts before the profile cascade tries to take the user's custom
    // exercises with it.
    await h.exec('DELETE FROM workouts WHERE user_id = @id', {'id': ownerId});
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
    expect(push['import_id'], 'strong:2023-01-15 17:35:12#Push Day');
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
}

class _Harness extends DatabaseTestBase;
