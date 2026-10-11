@Tags(['db'])
library;

import 'package:heart/models/imports.dart';
import 'package:heart_models/heart_models.dart';
import 'package:test/test.dart';

import 'db_test_utility.dart';

/// The app's own CSV export through the import query. The file names its
/// workouts and exercises by id: a workout that is one of the user's own
/// counts as already imported, so the file imported back into the account it
/// came from creates nothing; in another account every workout is created
/// once under a fresh id, and a second run is a no-op reported as skips. An
/// exercise resolves by its id ahead of its name (the name is the catalog's
/// display copy in the app's language), and a name the database knows under
/// neither becomes a custom. A workout the user deleted is not "their own"
/// any more and comes back from the file, as it does from the other sources.
///
/// Tagged `db` — skipped by the default `dart test`. Run with:
///   dart test --run-skipped -t db
void main() {
  final h = _Harness();

  late String ownerId;
  late String benchId; // a library exercise the file names by id and by name
  late String benchName;
  late String squatId; // a library exercise the file names by id, under a German name
  late String squatName;
  late String squatDe;
  late String customName; // only in the file, with an id no account has
  late String ownWorkoutId; // the owner's own workout, as the file would have written it

  // a second workout the file carries that no account has yet
  final otherWorkoutId = uuidV7();
  final customId = uuidV7();

  // rows as the app's ExportSnapshot.toCsv writes them: one per set, ISO
  // instants in UTC, the unit on the row, exercise notes repeated per set.
  // The own workout's row carries a note its stored exercise lacks: the
  // user's own export must not fill it back in
  String csv() =>
      'workout_id,start,end,exercise_id,exercise_name,set_index,weight,unit,reps,duration,distance,notes\n'
      '$ownWorkoutId,2026-07-20T18:00:00.000Z,2026-07-20T19:00:00.000Z,$benchId,$benchName,1,100,kg,5,,,cleared since\n'
      '$otherWorkoutId,2026-07-22T18:00:00.000Z,2026-07-22T19:00:00.000Z,$squatId,$squatDe,1,176.37,lb,5,,,\n'
      '$otherWorkoutId,2026-07-22T18:00:00.000Z,2026-07-22T19:00:00.000Z,$squatId,$squatDe,2,176.37,lb,5,,,\n'
      '$otherWorkoutId,2026-07-22T18:00:00.000Z,2026-07-22T19:00:00.000Z,$customId,$customName,1,,,12,,,one hand at a time\n';

  Future<List<Map<String, dynamic>>> workoutsOf(String userId) async {
    final rows = await h.exec(
      'SELECT id::text AS id, import_id FROM workouts WHERE user_id = @u ORDER BY started_at',
      {'u': userId},
    );
    return [for (final r in rows) r.toColumnMap()];
  }

  setUpAll(() async {
    await h.setupDatabase();
    ownerId = await h.seedProfile();
    benchName = h.uniqueName('Bench Press (Barbell)');
    squatName = h.uniqueName('Squat (Barbell)');
    squatDe = h.uniqueName('Kniebeuge (Langhantel)');
    customName = h.uniqueName('Muffin pull-up');
    benchId = await h.seedGlobalExercise(name: benchName);
    squatId = await h.seedGlobalExercise(name: squatName);
    ownWorkoutId = await h.seedWorkout(
      userId: ownerId,
      start: DateTime.utc(2026, 7, 20, 18),
      end: DateTime.utc(2026, 7, 20, 19),
    );
    final weId = await h.insertId(
      'INSERT INTO workout_exercises (workout_id, exercise_id, exercise_order) VALUES (@w, @e, 0) RETURNING id',
      {'w': ownWorkoutId, 'e': benchId},
    );
    await h.exec(
      'INSERT INTO exercise_sets (workout_exercise_id, weight, reps, set_order) VALUES (@we, 100, 5, 0)',
      {'we': weId},
    );
  });

  final extraProfiles = <String>[];

  tearDownAll(() async {
    // workout_exercises.exercise_id is ON DELETE RESTRICT; drop the imported
    // workouts before the profile cascade takes the custom exercises with it
    await h.exec('DELETE FROM workouts WHERE user_id = ANY(@ids)', {
      'ids': [ownerId, ...extraProfiles],
    });
    await h.teardownDatabase();
  });

  test('the preview counts the user\'s own workout as already imported and matches the German title by id', () async {
    final batch = WorkoutImport.fromHeartCsv(csv());
    final preview = await h.db.previewImport(userId: ownerId, batch: batch);

    expect(preview.workoutsFound, 2);
    expect(preview.workoutsAlreadyImported, 1);
    expect(preview.workoutsEnriched, 0);
    expect(preview.exercisesMatched, 2);
    expect(preview.exercisesUnmatched.map((e) => e.name), [customName]);
  });

  test('imported back into its own account, the file creates only what the account lacks', () async {
    final batch = WorkoutImport.fromHeartCsv(csv());
    final report = await h.db.importWorkouts(userId: ownerId, batch: batch);

    expect(report.source, 'heart');
    expect(report.workoutsFound, 2);
    expect(report.workoutsCreated, 1);
    expect(report.workoutsEnriched, 0);
    expect(report.workoutsSkipped, 1);
    expect(report.setsCreated, 3);
    expect(report.exercisesMatched, 2);
    expect(report.exercisesCreated, [customName]);

    final stored = await workoutsOf(ownerId);
    expect(stored, hasLength(2));
    // the own workout is untouched: no import identity, same id, and the note
    // the file carries is not written back
    expect(stored.first, {'id': ownWorkoutId, 'import_id': null});
    final ownNotes = await h.exec('SELECT note FROM workout_exercises WHERE workout_id = @w::uuid', {
      'w': ownWorkoutId,
    });
    expect(ownNotes.single.toColumnMap()['note'], isNull);
    // the other lands under a fresh id, never the file's, with the file's id as its identity
    expect(stored.last['id'], isNot(otherWorkoutId));
    expect(stored.last['import_id'], 'heart:$otherWorkoutId');

    final exercises = await h.exec(
      'SELECT we.exercise_id::text AS id, e.name '
      'FROM workout_exercises we JOIN exercises e ON e.id = we.exercise_id '
      'WHERE we.workout_id = @w::uuid ORDER BY we.exercise_order',
      {'w': stored.last['id']},
    );
    expect(exercises.map((r) => r.toColumnMap()['id']).first, squatId);
    expect(exercises.map((r) => r.toColumnMap()['name']).last, customName);
  });

  test('a second run of the same file creates nothing and reports the skips', () async {
    final batch = WorkoutImport.fromHeartCsv(csv());
    final again = await h.db.importWorkouts(userId: ownerId, batch: batch);

    expect(again.workoutsCreated, 0);
    expect(again.workoutsEnriched, 0);
    expect(again.workoutsSkipped, 2);
    expect(again.setsCreated, 0);
    expect(again.exercisesCreated, isEmpty);
    expect(await workoutsOf(ownerId), hasLength(2));
  });

  test('in another account every workout is created once, under fresh ids', () async {
    final user = await h.seedProfile();
    extraProfiles.add(user);
    final batch = WorkoutImport.fromHeartCsv(csv());

    final report = await h.db.importWorkouts(userId: user, batch: batch);
    expect(report.workoutsCreated, 2);
    expect(report.setsCreated, 4);
    expect(report.exercisesCreated, [customName]);

    final stored = await workoutsOf(user);
    expect(stored.map((w) => w['id']), isNot(anyOf(contains(ownWorkoutId), contains(otherWorkoutId))));
    expect(stored.map((w) => w['import_id']), ['heart:$ownWorkoutId', 'heart:$otherWorkoutId']);

    final again = await h.db.importWorkouts(userId: user, batch: batch);
    expect(again.workoutsCreated, 0);
    expect(again.workoutsSkipped, 2);
  });

  test('a workout the user deleted comes back from the file, as from any other source', () async {
    await h.db.deleteWorkout(userId: ownerId, workoutId: ownWorkoutId);
    final batch = WorkoutImport.fromHeartCsv(csv());

    final report = await h.db.importWorkouts(userId: ownerId, batch: batch);
    expect(report.workoutsCreated, 1);
    expect(report.workoutsSkipped, 1);

    final stored = await workoutsOf(ownerId);
    expect(stored.map((w) => w['import_id']), ['heart:$ownWorkoutId', 'heart:$otherWorkoutId']);
    expect(stored.first['id'], isNot(ownWorkoutId));
  });
}

class _Harness extends DatabaseTestBase;
