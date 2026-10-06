@Tags(['db'])
library;

import 'package:heart/models/exports.dart';
import 'package:heart/models/imports.dart';
import 'package:heart_models/heart_models.dart';
import 'package:test/test.dart';

import 'db_test_utility.dart';

/// The Strong-format export against a live Postgres: import a Strong file,
/// export the account, import the export into a fresh account, and the two
/// histories match. Also the one-export-a-day allowance.
///
/// Tagged `db` — skipped by the default `dart test`. Run with:
///   dart test --run-skipped -t db
void main() {
  final h = _Harness();
  final profiles = <String>[];

  late String bench;
  late String custom;
  late String ruck;

  String strong() =>
      'Date,Workout Name,Duration,Exercise Name,Set Order,Weight,Reps,Distance,Seconds,Notes,Workout Notes,RPE\n'
      '2023-01-15 17:35:12,"Push, heavy",1h 10m,"$bench",W,40,10,0,0,"elbow ok","felt ""strong""",\n'
      '2023-01-15 17:35:12,"Push, heavy",1h 10m,"$bench",1,80,5,0,0,,"felt ""strong""",8\n'
      '2023-01-15 17:35:12,"Push, heavy",1h 10m,"$bench",2,85,3,0,0,,"felt ""strong""",9.5\n'
      '2023-01-15 17:35:12,"Push, heavy",1h 10m,"$bench",D,60,8,0,0,,"felt ""strong""",\n'
      '2023-01-15 17:35:12,"Push, heavy",1h 10m,"$custom",1,25.5,12,0,0,,"felt ""strong""",\n'
      '2023-01-17 08:00:00,Morning Run,45min,"$ruck",1,0,0,5.2,1800,,,\n';

  Future<String> profile() async {
    final id = await h.seedProfile();
    profiles.add(id);
    return id;
  }

  Future<List<Workout>> everything(String userId) async {
    final all = <Workout>[];
    String? cursor;
    do {
      final page = await h.db.getWorkouts(
        userId: userId,
        targetUserId: userId,
        cursor: cursor,
        limit: 100,
        imageUrl: (k) => k,
      );
      all.addAll(page.items);
      cursor = page.hasMore ? page.items.last.id : null;
    } while (cursor != null);
    return all.reversed.toList();
  }

  /// What a Strong file can carry, per workout, in a comparable form.
  List<Object?> projection(Iterable<Workout> workouts) {
    return [
      for (final w in workouts)
        [
          w.name,
          w.start.toUtc(),
          w.end?.toUtc(),
          w.note,
          for (final e in w)
            [
              e.exercise.name,
              e.note,
              for (final s in e.where((s) => s.isCompleted))
                [s.setType, s.weight, s.reps, s.distance, s.duration, s.rpe],
            ],
        ],
    ];
  }

  setUpAll(() async {
    await h.setupDatabase();
    bench = h.uniqueName('Bench');
    custom = h.uniqueName('Kit Special Press');
    ruck = h.uniqueName('Ruck');
    await h.seedGlobalExercise(name: bench);
  });

  tearDownAll(() async {
    // workout_exercises.exercise_id is RESTRICT: drop the workouts before the
    // profile cascade tries to take the custom exercises with it.
    await h.exec('DELETE FROM workouts WHERE user_id = ANY(@ids)', {'ids': profiles});
    await h.teardownDatabase();
  });

  test('an export imports back into the same history', () async {
    final original = await profile();
    await h.db.importWorkouts(userId: original, batch: WorkoutImport.fromStrongCsv(strong()));
    final before = await everything(original);
    expect(before, hasLength(2));

    final csv = strongCsv(before);

    final copy = await profile();
    final report = await h.db.importWorkouts(userId: copy, batch: WorkoutImport.fromStrongCsv(csv));
    expect(report.toMap()['rowsSkipped'] ?? 0, 0);

    expect(projection(await everything(copy)), projection(before));
  });

  test('imperial exports convert and re-import to the same kilograms', () async {
    final original = await profile();
    await h.db.importWorkouts(userId: original, batch: WorkoutImport.fromStrongCsv(strong()));
    final before = await everything(original);

    final csv = strongCsv(before, unit: .imperial);
    expect(csv, contains(',176.37,')); // 80 kg

    final copy = await profile();
    await h.db.importWorkouts(
      userId: copy,
      batch: WorkoutImport.fromStrongCsv(csv, unit: .imperial),
    );
    final after = await everything(copy);
    final weights = [
      for (final w in after)
        for (final e in w)
          for (final s in e) s.weight,
    ];
    final expected = [
      for (final w in before)
        for (final e in w)
          for (final s in e) s.weight,
    ];
    expect(weights, hasLength(expected.length));
    for (final (i, kg) in weights.indexed) {
      expect(kg, expected[i] == null ? isNull : closeTo(expected[i]!, 0.01));
    }
  });

  test('one export a day', () async {
    final user = await profile();
    await h.exec('INSERT INTO api_usage (user_id) VALUES (@u)', {'u': user});

    expect(await h.db.claimExport(user), isNull);
    final refused = await h.db.claimExport(user);
    expect(refused, isNotNull);

    await h.exec("UPDATE api_usage SET last_export_at = now() - interval '25 hours' WHERE user_id = @u", {'u': user});
    expect(await h.db.claimExport(user), isNull);
  });
}

class _Harness extends DatabaseTestBase;
