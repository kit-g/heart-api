import 'package:heart/models/imports.dart';
import 'package:heart_models/heart_models.dart';
import 'package:test/test.dart';

/// A realistic Strong export: one row per set, quoted fields with embedded
/// commas/quotes, zeros meaning "unset", and an RPE column we ignore.
const _strongCsv =
    'Date,Workout Name,Duration,Exercise Name,Set Order,Weight,Reps,Distance,Seconds,Notes,Workout Notes,RPE\n'
    '2023-01-15 17:35:12,Push Day,1h 10m,Bench Press (Barbell),1,80,5,0,0,,,8\n'
    '2023-01-15 17:35:12,Push Day,1h 10m,Bench Press (Barbell),2,85,3,0,0,,,9\n'
    '2023-01-15 17:35:12,Push Day,1h 10m,"Fly, Seated (Cable)",1,25,12,0,0,"felt ""good""",,\n'
    '2023-01-17 08:00:00,Morning Run,45m,Running,1,0,0,5.2,1800,,,\n'
    '2023-01-18 18:00:00,Core,30m,Plank,1,0,0,0,60,,,\n'
    '2023-01-18 18:00:00,Core,30m,Sit Up,1,0,15,0,0,,,\n';

void main() {
  group('WorkoutImport.fromStrongCsv', () {
    final batch = WorkoutImport.fromStrongCsv(_strongCsv);

    test('groups one-row-per-set into workouts by date and name', () {
      expect(batch.workouts, hasLength(3));
      expect(batch.workouts.map((w) => w.name), ['Push Day', 'Morning Run', 'Core']);
      expect(batch.rowsSkipped, 0);
    });

    test('groups sets under their exercise, preserving first-appearance order', () {
      final push = batch.workouts.first;
      expect(push.exercises.map((e) => e.name), ['Bench Press (Barbell)', 'Fly, Seated (Cable)']);
      expect(push.exercises.first.sets, hasLength(2));
    });

    test('parses set measurements, mapping zero to null', () {
      final bench = batch.workouts.first.exercises.first.sets;
      expect(bench.first.weight, 80);
      expect(bench.first.reps, 5);
      expect(bench.first.distance, isNull);
      expect(bench.first.duration, isNull);

      final run = batch.workouts[1].exercises.single.sets.single;
      expect(run.weight, isNull);
      expect(run.distance, 5.2);
      expect(run.duration, 1800);
    });

    test('derives the workout window from Date plus Duration', () {
      final push = batch.workouts.first;
      expect(push.start, DateTime.utc(2023, 1, 15, 17, 35, 12));
      expect(push.end, DateTime.utc(2023, 1, 15, 18, 45, 12));
    });

    test('pins naive local timestamps using the device utc offset', () {
      final shifted = WorkoutImport.fromStrongCsv(_strongCsv, utcOffset: const Duration(hours: 2));
      expect(shifted.workouts.first.start, DateTime.utc(2023, 1, 15, 15, 35, 12));
    });

    test('derives a deterministic, opaque import id from the source row', () {
      // sha256('2023-01-15 17:35:12|Push Day') — pinned so a hash-input change
      // (which would orphan dedup against already-imported rows) fails loudly
      expect(batch.workouts.first.importId, 'strong:b5f8d5d78f2427ef');
      final again = WorkoutImport.fromStrongCsv(_strongCsv);
      expect(again.workouts.first.importId, batch.workouts.first.importId);
    });

    test('import ids are distinct per workout and leak nothing of the source', () {
      final ids = batch.workouts.map((w) => w.importId).toSet();
      expect(ids, hasLength(batch.workouts.length));
      for (final id in ids) {
        expect(id, matches(r'^strong:[0-9a-f]{16}$'));
      }
    });

    test('the import id ignores the tz offset, so re-uploads from another timezone still dedup', () {
      final shifted = WorkoutImport.fromStrongCsv(_strongCsv, utcOffset: const Duration(hours: 2));
      expect(shifted.workouts.first.importId, batch.workouts.first.importId);
    });

    test('lists distinct exercises with inferred categories', () {
      final byName = {for (final e in batch.exercises) e['name']: e};
      expect(byName.keys, hasLength(5));
      expect(byName['Bench Press (Barbell)']!['category'], 'Barbell');
      expect(byName['Fly, Seated (Cable)']!['category'], 'Machine');
      expect(byName['Running']!['category'], 'Cardio');
      expect(byName['Plank']!['category'], 'Duration');
      expect(byName['Sit Up']!['category'], 'Reps Only');
      expect(byName.values.every((e) => e['target'] == 'Other'), isTrue);
    });

    test('skips and counts unparseable rows instead of failing the batch', () {
      final withBadRow =
          '$_strongCsv'
          '2023-01-19 10:00:00,Legs,20m,Squat (Barbell),1,not-a-number,5,0,0,,,\n';
      final parsed = WorkoutImport.fromStrongCsv(withBadRow);
      expect(parsed.rowsSkipped, 1);
      expect(parsed.workouts, hasLength(3));
    });

    test('repairs rows shifted by an unquoted thousands separator in Duration', () {
      // Strong exports a runaway workout as "3,527h 3min" without quoting,
      // splitting the field and pushing every later column one to the right
      const csv =
          'Date,Workout Name,Duration,Exercise Name,Set Order,Weight,Reps,Distance,Seconds,Notes,Workout Notes,RPE\n'
          '2024-07-22 17:45:06,"Legs",3,527h 3min,"Leg Press",1,450.0,12.0,0,0.0,"","",\n';
      final batch = WorkoutImport.fromStrongCsv(csv);
      final workout = batch.workouts.single;
      expect(workout.exercises.single.name, 'Leg Press');
      expect(workout.exercises.single.sets.single.weight, 450);
      expect(workout.exercises.single.sets.single.reps, 12);
      expect(batch.rowsSkipped, 0);
    });

    test('drops the end timestamp when the duration is a left-running artifact', () {
      const csv =
          'Date,Workout Name,Duration,Exercise Name,Weight,Reps\n'
          '2024-07-22 17:45:06,Legs,"3,527h 3min",Squat (Barbell),100,5\n'
          '2024-07-23 17:45:06,Push,12h 56min,Bench Press (Barbell),80,5\n';
      final batch = WorkoutImport.fromStrongCsv(csv);
      expect(batch.workouts.first.end, isNull);
      // under 24h is kept — a long day is not corrupt data
      expect(batch.workouts.last.end, DateTime.utc(2024, 7, 24, 6, 41, 6));
    });

    test('an oversized export keeps only the most recent workouts, in file order', () {
      // one workout per hour, oldest first, 50 past the cap
      final buffer = StringBuffer('Date,Workout Name,Duration,Exercise Name,Weight,Reps\n');
      final epoch = DateTime.utc(2020, 1, 1);
      for (var n = 0; n < WorkoutImport.maxWorkouts + 50; n++) {
        final start = epoch.add(Duration(hours: n)).toIso8601String().replaceFirst('T', ' ').substring(0, 19);
        buffer.writeln('$start,W$n,1h,Bench Press (Barbell),100,5');
      }
      final batch = WorkoutImport.fromStrongCsv(buffer.toString());

      expect(batch.workouts, hasLength(WorkoutImport.maxWorkouts));
      expect(batch.workoutsDropped, 50);
      // the oldest 50 are the ones dropped...
      expect(batch.workouts.first.name, 'W50');
      // ...and the survivors keep their file (chronological) order
      expect(batch.workouts.last.name, 'W${WorkoutImport.maxWorkouts + 49}');
    });

    test('an export within the cap drops nothing', () {
      expect(batch.workoutsDropped, 0);
    });

    test('rejects a file without the Strong columns', () {
      expect(() => WorkoutImport.fromStrongCsv('a,b,c\n1,2,3\n'), throwsFormatException);
      expect(() => WorkoutImport.fromStrongCsv(''), throwsFormatException);
    });
  });

  group('unit handling', () {
    test('metric fallback stores weights as-is', () {
      final batch = WorkoutImport.fromStrongCsv(_strongCsv);
      expect(batch.workouts.first.exercises.first.sets.first.weight, 80);
    });

    test('imperial fallback converts lbs to kg and miles to km', () {
      final batch = WorkoutImport.fromStrongCsv(_strongCsv, unit: MeasurementUnit.imperial);
      expect(batch.workouts.first.exercises.first.sets.first.weight, closeTo(36.29, 0.01));
      expect(batch.workouts[1].exercises.single.sets.single.distance, closeTo(8.37, 0.01));
    });

    test('a Weight Unit column beats the fallback, per row', () {
      const csv =
          'Date,Workout Name,Duration,Exercise Name,Weight,Weight Unit,Reps\n'
          '2023-01-15 17:35:12,Mixed,1h,Bench Press (Barbell),100,lbs,5\n'
          '2023-01-15 17:35:12,Mixed,1h,Squat (Barbell),100,kg,5\n';
      final batch = WorkoutImport.fromStrongCsv(csv);
      final sets = [for (final e in batch.workouts.single.exercises) e.sets.single];
      expect(sets.first.weight, closeTo(45.36, 0.01));
      expect(sets.last.weight, 100);
    });

    test('a unit baked into the header ("Weight (kg)") beats the fallback', () {
      const csv =
          'Date,Workout Name,Exercise Name,Weight (kg),Reps\n'
          '2023-01-15 17:35:12,Push,Bench Press (Barbell),100,5\n';
      final batch = WorkoutImport.fromStrongCsv(csv, unit: MeasurementUnit.imperial);
      expect(batch.workouts.single.exercises.single.sets.single.weight, 100);
    });

    test('"Distance (meters)" converts to kilometers', () {
      const csv =
          'Date,Workout Name,Exercise Name,Distance (meters),Seconds\n'
          '2023-01-15 17:35:12,Run,Running,5200,1800\n';
      final batch = WorkoutImport.fromStrongCsv(csv);
      expect(batch.workouts.single.exercises.single.sets.single.distance, closeTo(5.2, 0.001));
    });

    test('semicolon-delimited exports with decimal commas parse', () {
      const csv =
          'Date;Workout Name;Duration;Exercise Name;Weight;Reps\n'
          '2023-01-15 17:35:12;Push;1h;Bench Press (Barbell);82,5;5\n';
      final batch = WorkoutImport.fromStrongCsv(csv);
      expect(batch.workouts.single.exercises.single.sets.single.weight, 82.5);
    });
  });

  group('payload and report', () {
    test('toParams encodes workouts and exercises as JSON strings', () {
      final params = WorkoutImport.fromStrongCsv(_strongCsv).toParams(userId: 'u1');
      expect(params['userId'], 'u1');
      expect(params['workouts'], isA<String>());
      expect(params['exercises'], isA<String>());
      expect(params['workouts'], contains('"importId":"strong:b5f8d5d78f2427ef"'));
    });

    test('set payload omits null measurements', () {
      const set = ImportedSet(weight: 80, reps: 5);
      expect(set.toPayload(), {'weight': 80, 'reps': 5});
    });

    test('report round-trips from a result row and derives workoutsSkipped', () {
      final report = WorkoutImportReport.fromRow(
        {
          'workouts_found': 10,
          'workouts_created': 7,
          'sets_created': 120,
          'sets_skipped': 4,
          'exercises_matched': 15,
          'exercises_created': ['Custom Curl'],
          'exercises_skipped': ['Free motion Row'],
        },
        source: 'strong',
        rowsSkipped: 2,
        workoutsDropped: 1,
      );
      expect(report.toMap(), {
        'source': 'strong',
        'workoutsFound': 10,
        'workoutsCreated': 7,
        'workoutsSkipped': 3,
        'workoutsDropped': 1,
        'setsCreated': 120,
        'setsSkipped': 4,
        'exercisesMatched': 15,
        'exercisesCreated': ['Custom Curl'],
        'exercisesSkipped': ['Free motion Row'],
        'rowsSkipped': 2,
      });
    });

    test('counts sets per exercise name across the batch', () {
      final batch = WorkoutImport.fromStrongCsv(_strongCsv);
      expect(batch.setsByExercise['Bench Press (Barbell)'], 2);
      expect(batch.setsByExercise['Running'], 1);
      expect(batch.setsFound, 6);
    });

    test('preview combines the resolve row with counts from the batch', () {
      final batch = WorkoutImport.fromStrongCsv(_strongCsv);
      final preview = WorkoutImportPreview.fromRow(
        {
          'workouts_already_imported': 1,
          'exercises_matched': ['Bench Press (Barbell)', 'Running'],
        },
        batch: batch,
      );
      expect(preview.toMap(), {
        'source': 'strong',
        'workoutsFound': 3,
        'workoutsAlreadyImported': 1,
        'workoutsDropped': 0,
        'setsFound': 6,
        'exercisesMatched': 2,
        'exercisesUnmatched': [
          {'name': 'Fly, Seated (Cable)', 'sets': 1},
          {'name': 'Plank', 'sets': 1},
          {'name': 'Sit Up', 'sets': 1},
        ],
        'rowsSkipped': 0,
      });
    });
  });

  group('parseCsv', () {
    test('keeps quoted delimiters, escaped quotes, and newlines in one field', () {
      final rows = parseCsv('a,"b,\nc","d""e"\n1,2,3\n');
      expect(rows, [
        ['a', 'b,\nc', 'd"e'],
        ['1', '2', '3'],
      ]);
    });

    test('handles CRLF rows and drops fully empty lines', () {
      final rows = parseCsv('a,b\r\n\r\n1,2\r\n');
      expect(rows, [
        ['a', 'b'],
        ['1', '2'],
      ]);
    });

    test('keeps the last row without a trailing newline', () {
      expect(parseCsv('a,b\n1,2'), [
        ['a', 'b'],
        ['1', '2'],
      ]);
    });
  });
}
