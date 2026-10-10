import 'package:heart/models/imports.dart';
import 'package:heart_models/heart_models.dart';
import 'package:test/test.dart';

/// A realistic Strong export: one row per set, quoted fields with embedded
/// commas/quotes, zeros meaning "unset", an RPE column — and a "Rest Timer"
/// row, which Strong interleaves after any set that ran one. Every set count
/// below is blind to it: it is structure, not a set.
const _strongCsv =
    'Date,Workout Name,Duration,Exercise Name,Set Order,Weight,Reps,Distance,Seconds,Notes,Workout Notes,RPE\n'
    '2023-01-15 17:35:12,Push Day,1h 10m,Bench Press (Barbell),1,80,5,0,0,,,8\n'
    '2023-01-15 17:35:12,Push Day,1h 10m,Bench Press (Barbell),Rest Timer,0,0,0,120,,,\n'
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

    test('a loaded carry or hold keeps its weight in a weighted category', () {
      const csv =
          'Date,Workout Name,Duration,Exercise Name,Set Order,Weight,Reps,Distance,Seconds\n'
          '2023-02-01 10:00:00,Strongman,45m,Farmers Walk,1,40,0,0.05,0\n'
          '2023-02-01 10:00:00,Strongman,45m,Weighted Plank,1,20,0,0,60\n';
      final byName = {for (final e in WorkoutImport.fromStrongCsv(csv).exercises) e['name']: e};
      expect(byName['Farmers Walk']!['category'], 'Weighted Distance');
      expect(byName['Weighted Plank']!['category'], 'Weighted Duration');
    });

    test('Rest Timer rows are never sets; warm-up/drop/failure are — Set Order letters are sets', () {
      const csv =
          'Date,Workout Name,Duration,Exercise Name,Set Order,Weight,Reps\n'
          '2023-02-01 10:00:00,Back,45m,Lat Pulldown (Cable),W,20,12\n'
          '2023-02-01 10:00:00,Back,45m,Lat Pulldown (Cable),1,48,8\n'
          '2023-02-01 10:00:00,Back,45m,Lat Pulldown (Cable),Rest Timer,0,0\n'
          '2023-02-01 10:00:00,Back,45m,Lat Pulldown (Cable),D,41,10\n'
          '2023-02-01 10:00:00,Back,45m,Lat Pulldown (Cable),F,34,12\n';
      final batch = WorkoutImport.fromStrongCsv(csv);
      final sets = batch.workouts.single.exercises.single.sets;
      expect(sets, hasLength(4));
      expect(sets.map((s) => s.weight), [20, 48, 41, 34]);
      // structure, not a bad row — nothing to alarm the report over
      expect(batch.rowsSkipped, 0);
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

    test('an export within the caps drops nothing', () {
      expect(batch.workoutsDropped, 0);
      expect(batch.setsDropped, 0);
    });

    test('a workout stuffed past the per-workout set cap keeps only its first sets', () {
      final buffer = StringBuffer('Date,Workout Name,Duration,Exercise Name,Weight,Reps\n');
      for (var n = 0; n < WorkoutImport.maxSetsPerWorkout + 30; n++) {
        // spread across two exercises — the cap is per workout, not per exercise
        buffer.writeln('2023-01-15 17:35:12,Stuffed,1h,Exercise ${n % 2},${n + 1},5');
      }
      // a second, normal workout must be untouched by its sibling's overflow
      buffer.writeln('2023-01-16 08:00:00,Normal,1h,Running,0,5');
      final batch = WorkoutImport.fromStrongCsv(buffer.toString());

      expect(batch.setsDropped, 30);
      expect(batch.workoutsDropped, 0);
      final stuffed = batch.workouts.first;
      final total = stuffed.exercises.fold(0, (n, e) => n + e.sets.length);
      expect(total, WorkoutImport.maxSetsPerWorkout);
      // survivors are the file's first rows: weights 1..cap
      expect(stuffed.exercises.first.sets.first.weight, 1);
      expect(batch.workouts.last.exercises.single.sets, hasLength(1));
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

    test('a declared unit wins over the fallback however it is spelled: Strong\'s "mi." is miles', () {
      // the 2025 semicolon layout as a real export writes it (heart-api#162):
      // Weight Unit is `lbs`, Distance Unit is `mi.`, with the period
      const csv =
          'Date;Workout Name;Exercise Name;Set Order;Weight;Weight Unit;Reps;RPE;Distance;Distance Unit;Seconds;Notes;Workout Notes;Workout Duration\n'
          '2025-09-02 07:10:00;"Morning Ride";"Cycling";1;0.0;lbs;0.0;;10.0;mi.;1800.0;"";"";35m\n'
          '2025-09-02 07:10:00;"Morning Ride";"Bench Press (Barbell)";1;135.0;lbs;5.0;;0.0;mi.;0.0;"";"";35m\n';
      final batch = WorkoutImport.fromStrongCsv(csv);
      final (ride, bench) = (
        batch.workouts.single.exercises.first.sets.single,
        batch.workouts.single.exercises.last.sets.single,
      );
      expect(ride.distance, closeTo(16.09, 0.01));
      expect(bench.weight, closeTo(61.23, 0.01));

      final asImperial = WorkoutImport.fromStrongCsv(csv, unit: MeasurementUnit.imperial);
      expect(asImperial.workouts.single.exercises.first.sets.single.distance, closeTo(16.09, 0.01));
    });

    test('Kilometers, kms, metres and KM. all read as what they say', () {
      String csv(String unit) =>
          'Date,Workout Name,Exercise Name,Distance,Distance Unit\n'
          '2023-01-15 17:35:12,Run,Running,5,$unit\n';
      double distance(String unit) => WorkoutImport.fromStrongCsv(
        csv(unit),
        unit: MeasurementUnit.imperial,
      ).workouts.single.exercises.single.sets.single.distance!;
      expect(distance('Kilometers'), 5);
      expect(distance('kms'), 5);
      expect(distance('KM.'), 5);
      expect(distance('metres'), 0.005);
      expect(distance('mile'), closeTo(8.05, 0.01));
    });
  });

  group('set type, RPE, notes and rest timers (rows from real exports)', () {
    // content/assets/strong_workouts.csv, the old comma layout
    const oldHeader =
        'Date,Workout Name,Duration,Exercise Name,Set Order,Weight,Reps,Distance,Seconds,Notes,Workout Notes,RPE\n';
    // a 2025 export in the newer semicolon layout, which moved RPE next to Reps
    const newHeader =
        'Date;Workout Name;Exercise Name;Set Order;Weight;Weight Unit;Reps;RPE;Distance;Distance Unit;Seconds;Notes;Workout Notes;Workout Duration\n';

    const chestDip =
        '$oldHeader'
        '2025-07-14 20:44:18,"Evening Workout",1h 22min,"Chest Dip",W,0.0,16.0,0,0.0,"","",\n'
        '2025-07-14 20:44:18,"Evening Workout",1h 22min,"Chest Dip",1,45.0,18.0,0,0.0,,,\n'
        '2025-07-14 20:44:18,"Evening Workout",1h 22min,"Chest Dip",Rest Timer,0,0.0,0,120.0,,,\n'
        '2025-07-14 20:44:18,"Evening Workout",1h 22min,"Chest Dip",2,45.0,18.0,0,0.0,,,\n'
        '2025-07-14 20:44:18,"Evening Workout",1h 22min,"Chest Dip",Rest Timer,0,0.0,0,120.0,,,\n'
        '2025-07-14 20:44:18,"Evening Workout",1h 22min,"Chest Dip",3,45.0,25.0,0,0.0,,,\n'
        '2025-07-14 20:44:18,"Evening Workout",1h 22min,"Chest Dip",Rest Timer,0,0.0,0,25.0,,,\n'
        '2025-07-14 20:44:18,"Evening Workout",1h 22min,"Lat Pulldown (Cable)",1,60.0,12.0,0,0.0,"",,\n'
        '2025-07-14 20:44:18,"Evening Workout",1h 22min,"Lat Pulldown (Cable)",Rest Timer,0,0.0,0,120.0,,,\n';

    test('Set Order maps to a set type: W/D/F their kinds, a number null — normal', () {
      const csv =
          'Date,Workout Name,Duration,Exercise Name,Set Order,Weight,Reps\n'
          '2023-02-01 10:00:00,Back,45m,Lat Pulldown (Cable),W,20,12\n'
          '2023-02-01 10:00:00,Back,45m,Lat Pulldown (Cable),1,48,8\n'
          '2023-02-01 10:00:00,Back,45m,Lat Pulldown (Cable),D,41,10\n'
          '2023-02-01 10:00:00,Back,45m,Lat Pulldown (Cable),F,34,12\n';
      final sets = WorkoutImport.fromStrongCsv(csv).workouts.single.exercises.single.sets;
      expect(sets.map((s) => s.type), ['warmup', null, 'drop', 'failure']);
    });

    test('an export without a Set Order column has only normal sets', () {
      const csv =
          'Date;Workout Name;Duration;Exercise Name;Weight;Reps\n'
          '2023-01-15 17:35:12;Push;1h;Bench Press (Barbell);82,5;5\n';
      expect(WorkoutImport.fromStrongCsv(csv).workouts.single.exercises.single.sets.single.type, isNull);
    });

    test('RPE is read in both layouts, half steps included', () {
      const csv =
          '$newHeader'
          '2025-01-13 20:55:44;"Qwer";"Bulgarian Split Squat";1;11;lbs;11;6.5;;;0;"";;6m\n';
      final set = WorkoutImport.fromStrongCsv(csv).workouts.single.exercises.single.sets.single;
      expect(set.rpe, 6.5);
      expect(set.reps, 11);

      final old = WorkoutImport.fromStrongCsv(_strongCsv).workouts.first.exercises.first.sets;
      expect(old.map((s) => s.rpe), [8, 9]);
    });

    test('an RPE off the half-step 1-10 scale is dropped, and the set still imports', () {
      const csv =
          '$newHeader'
          '2025-01-13 20:55:44;"Qwer";"Bulgarian Split Squat";1;11;lbs;11;8.3;;;0;"";;6m\n'
          '2025-01-13 20:55:44;"Qwer";"Bulgarian Split Squat";2;11;lbs;11;11;;;0;"";;6m\n'
          '2025-01-13 20:55:44;"Qwer";"Bulgarian Split Squat";3;11;lbs;11;hard;;;0;"";;6m\n';
      final batch = WorkoutImport.fromStrongCsv(csv);
      final sets = batch.workouts.single.exercises.single.sets;
      expect(sets, hasLength(3));
      expect(sets.map((s) => s.rpe), [null, null, null]);
      expect(batch.rowsSkipped, 0);
    });

    test('a note on the first set row becomes the exercise note', () {
      const csv =
          '$oldHeader'
          '2022-04-22 09:33:18,"Morning Workout",29min,"Chin Up",1,0,12.0,0,0.0,"Superset with shoulder press",,\n'
          '2022-04-22 09:33:18,"Morning Workout",29min,"Chin Up",2,0,12.0,0,0.0,,,\n'
          '2022-04-22 09:33:18,"Morning Workout",29min,"Chin Up",3,0,12.0,0,0.0,,,\n'
          '2022-04-22 09:33:18,"Morning Workout",29min,"Lateral Raise (Cable)",1,9.0,14.0,0,0.0,"",,\n';
      final workout = WorkoutImport.fromStrongCsv(csv).workouts.single;
      expect(workout.exercises.map((e) => e.note), ['Superset with shoulder press', null]);
      expect(workout.note, isNull);
    });

    test('distinct notes across an exercise\'s rows are kept once each, in order', () {
      const csv =
          '$oldHeader'
          '2022-04-22 09:33:18,"Morning Workout",29min,"Chin Up",1,0,12.0,0,0.0,"wide grip",,\n'
          '2022-04-22 09:33:18,"Morning Workout",29min,"Chin Up",2,0,12.0,0,0.0,"wide grip",,\n'
          '2022-04-22 09:33:18,"Morning Workout",29min,"Chin Up",3,0,12.0,0,0.0,"then neutral",,\n';
      expect(WorkoutImport.fromStrongCsv(csv).workouts.single.exercises.single.note, 'wide grip\nthen neutral');
    });

    test('Workout Notes becomes the workout note', () {
      const csv =
          '$newHeader'
          '2025-01-13 20:55:44;"Qwer";"Ab Wheel";1;11;lbs;11;;;;0;"";"deload week";6m\n';
      expect(WorkoutImport.fromStrongCsv(csv).workouts.single.note, 'deload week');
    });

    test('notes past the column bounds are cut, never split mid-character', () {
      final long = '💪' * 600;
      final csv =
          '$oldHeader'
          '2022-04-22 09:33:18,"Morning Workout",29min,"Chin Up",1,0,12.0,0,0.0,"$long","${'n' * 1200}",\n';
      final workout = WorkoutImport.fromStrongCsv(csv).workouts.single;
      expect(workout.exercises.single.note!.runes, hasLength(ImportedExercise.maxNoteLength));
      expect(workout.exercises.single.note, '💪' * ImportedExercise.maxNoteLength);
      expect(workout.note, hasLength(ImportedWorkout.maxNoteLength));
    });

    test('a row repaired for a runaway duration keeps its note columns aligned', () {
      // unrepaired, Seconds ("0.0") would sit under Notes
      const csv =
          '$oldHeader'
          '2024-07-22 17:45:06,"Legs",3,527h 3min,"Leg Press",1,450.0,12.0,0,0.0,"","",\n';
      final workout = WorkoutImport.fromStrongCsv(csv).workouts.single;
      expect(workout.exercises.single.note, isNull);
      expect(workout.note, isNull);
    });

    test('rest timer rows feed the exercise, never its sets', () {
      final batch = WorkoutImport.fromStrongCsv(chestDip);
      final dip = batch.workouts.single.exercises.first;
      expect(dip.sets, hasLength(4));
      expect(dip.restTimers, [120, 120, 25]);
      // including the timer after an exercise's last set
      expect(batch.workouts.single.exercises.last.restTimers, [120]);
      expect(batch.rowsSkipped, 0);
    });

    test('the exercise\'s timer is the most frequent one in its session, a nudged one aside', () {
      expect(WorkoutImport.fromStrongCsv(chestDip).restTimers, {'Chest Dip': 120, 'Lat Pulldown (Cable)': 120});
    });

    test('the most recent session with timers decides, whatever the file order', () {
      const csv =
          '$oldHeader'
          '2025-07-14 20:44:18,"Evening Workout",1h 22min,"Chest Dip",1,45.0,18.0,0,0.0,,,\n'
          '2025-07-14 20:44:18,"Evening Workout",1h 22min,"Chest Dip",Rest Timer,0,0.0,0,120.0,,,\n'
          '2025-05-27 19:13:27,"Evening Workout",39min,"Chest Dip",1,45.0,0.0,0,0.0,"","",\n'
          '2025-05-27 19:13:27,"Evening Workout",39min,"Chest Dip",Rest Timer,0,0.0,0,90.0,,,\n'
          '2025-08-01 19:00:00,"Evening Workout",40min,"Chest Dip",1,45.0,15.0,0,0.0,,,\n';
      // the August session ran no timer, so July's is the latest that says anything
      expect(WorkoutImport.fromStrongCsv(csv).restTimers, {'Chest Dip': 120});
    });

    test('a tie goes to the longer timer', () {
      const csv =
          '$oldHeader'
          '2025-07-14 20:44:18,"Evening Workout",1h 22min,"Chest Dip",1,45.0,18.0,0,0.0,,,\n'
          '2025-07-14 20:44:18,"Evening Workout",1h 22min,"Chest Dip",Rest Timer,0,0.0,0,90.0,,,\n'
          '2025-07-14 20:44:18,"Evening Workout",1h 22min,"Chest Dip",2,45.0,18.0,0,0.0,,,\n'
          '2025-07-14 20:44:18,"Evening Workout",1h 22min,"Chest Dip",Rest Timer,0,0.0,0,120.0,,,\n';
      expect(WorkoutImport.fromStrongCsv(csv).restTimers, {'Chest Dip': 120});
    });

    test('a timer after a warm-up is Strong\'s warm-up timer, not the exercise\'s', () {
      const csv =
          '$oldHeader'
          '2025-07-17 20:55:32,"Evening Workout",55min,"Calf Press on Leg Press",W,250.0,12.0,0,0.0,"",,\n'
          '2025-07-17 20:55:32,"Evening Workout",55min,"Calf Press on Leg Press",Rest Timer,0,0.0,0,60.0,,,\n'
          '2025-07-17 20:55:32,"Evening Workout",55min,"Calf Press on Leg Press",1,290.0,12.0,0,0.0,,,\n'
          '2025-07-17 20:55:32,"Evening Workout",55min,"Calf Press on Leg Press",Rest Timer,0,0.0,0,120.0,,,\n';
      final batch = WorkoutImport.fromStrongCsv(csv);
      expect(batch.workouts.single.exercises.single.restTimers, [120]);
      expect(batch.restTimers, {'Calf Press on Leg Press': 120});
    });

    test('a corrupt or absurd timer is ignored, never fatal', () {
      const csv =
          '$oldHeader'
          '2025-07-14 20:44:18,"Evening Workout",1h 22min,"Chest Dip",1,45.0,18.0,0,0.0,,,\n'
          '2025-07-14 20:44:18,"Evening Workout",1h 22min,"Chest Dip",Rest Timer,0,0.0,0,NaN,,,\n'
          '2025-07-14 20:44:18,"Evening Workout",1h 22min,"Chest Dip",2,45.0,18.0,0,0.0,,,\n'
          '2025-07-14 20:44:18,"Evening Workout",1h 22min,"Chest Dip",Rest Timer,0,0.0,0,Infinity,,,\n'
          '2025-07-14 20:44:18,"Evening Workout",1h 22min,"Chest Dip",3,45.0,18.0,0,0.0,,,\n'
          '2025-07-14 20:44:18,"Evening Workout",1h 22min,"Chest Dip",Rest Timer,0,0.0,0,9999999999,,,\n';
      final batch = WorkoutImport.fromStrongCsv(csv);
      expect(batch.workouts.single.exercises.single.sets, hasLength(3));
      expect(batch.restTimers, isEmpty);
      expect(batch.rowsSkipped, 0);
    });

    test('a NaN measurement skips its row instead of failing the import', () {
      const csv =
          '$oldHeader'
          '2025-07-14 20:44:18,"Evening Workout",1h 22min,"Chest Dip",1,NaN,18.0,0,0.0,,,\n'
          '2025-07-14 20:44:18,"Evening Workout",1h 22min,"Chest Dip",2,45.0,18.0,0,0.0,,,\n';
      final batch = WorkoutImport.fromStrongCsv(csv);
      expect(batch.rowsSkipped, 1);
      expect(batch.workouts.single.exercises.single.sets, hasLength(1));
    });

    test('a timer after a warm-up row is ignored even when that row failed to parse', () {
      const csv =
          '$oldHeader'
          '2025-07-17 20:55:32,"Evening Workout",55min,"Calf Press on Leg Press",1,290.0,12.0,0,0.0,,,\n'
          '2025-07-17 20:55:32,"Evening Workout",55min,"Calf Press on Leg Press",Rest Timer,0,0.0,0,120.0,,,\n'
          '2025-07-17 20:55:32,"Evening Workout",55min,"Calf Press on Leg Press",W,garbage,12.0,0,0.0,,,\n'
          '2025-07-17 20:55:32,"Evening Workout",55min,"Calf Press on Leg Press",Rest Timer,0,0.0,0,60.0,,,\n';
      final batch = WorkoutImport.fromStrongCsv(csv);
      expect(batch.rowsSkipped, 1);
      expect(batch.workouts.single.exercises.single.restTimers, [120]);
    });

    test('case-variant spellings share one latest session', () {
      const csv =
          '$oldHeader'
          '2023-01-10 18:00:00,"Push",1h,"Bench Press (Barbell)",1,80,5,0,0,,,\n'
          '2023-01-10 18:00:00,"Push",1h,"Bench Press (Barbell)",Rest Timer,0,0,0,180,,,\n'
          '2025-01-10 18:00:00,"Push",1h,"bench press (barbell)",1,90,5,0,0,,,\n'
          '2025-01-10 18:00:00,"Push",1h,"bench press (barbell)",Rest Timer,0,0,0,90,,,\n';
      expect(WorkoutImport.fromStrongCsv(csv).restTimers, {'bench press (barbell)': 90});
    });

    test('an export without rest timers gives the same sets, in the same positions', () {
      final withoutTimers = chestDip.split('\n').where((row) => !row.contains('Rest Timer')).join('\n');
      final a = WorkoutImport.fromStrongCsv(chestDip).workouts.single;
      final b = WorkoutImport.fromStrongCsv(withoutTimers).workouts.single;
      expect(b.importId, a.importId);
      expect(
        [
          for (final e in b.exercises)
            for (final s in e.sets) s.toPayload(),
        ],
        [
          for (final e in a.exercises)
            for (final s in e.sets) s.toPayload(),
        ],
      );
      expect(WorkoutImport.fromStrongCsv(withoutTimers).restTimers, isEmpty);
    });

    test('the payload carries set type, RPE, notes and the rest timers', () {
      final params = WorkoutImport.fromStrongCsv(chestDip).toParams(userId: 'u1');
      expect(params['workouts'], contains('"setType":"warmup"'));
      expect(
        params['restTimers'],
        '[{"name":"Chest Dip","seconds":120},{"name":"Lat Pulldown (Cable)","seconds":120}]',
      );
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
      const typed = ImportedSet(weight: 80, reps: 5, type: 'warmup', rpe: 6.5);
      expect(typed.toPayload(), {'weight': 80, 'reps': 5, 'setType': 'warmup', 'rpe': 6.5});
    });

    test('report round-trips from a result row and derives workoutsSkipped', () {
      final report = WorkoutImportReport.fromRow(
        {
          'workouts_found': 3,
          'workouts_created': 1,
          'workouts_enriched': 1,
          'sets_created': 5,
          'sets_enriched': 4,
          'rest_timers_set': 2,
          'sets_skipped': 1,
          'exercises_matched': 4,
          'exercises_created': ['Custom Curl'],
          'exercises_skipped': ['Free motion Row'],
        },
        batch: WorkoutImport.fromStrongCsv(_strongCsv),
      );
      expect(report.toMap(), {
        'source': 'strong',
        'workoutsFound': 3,
        'workoutsCreated': 1,
        'workoutsEnriched': 1,
        // an enriched workout is not a skipped one
        'workoutsSkipped': 1,
        'workoutsDropped': 0,
        'setsCreated': 5,
        'setsEnriched': 4,
        'setsSkipped': 1,
        'setsDropped': 0,
        'exercisesMatched': 4,
        'exercisesCreated': ['Custom Curl'],
        'exercisesSkipped': ['Free motion Row'],
        'restTimersSet': 2,
        'rowsSkipped': 0,
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
          'workouts_enriched': 1,
          'sets_enriched': 2,
          'rest_timers_set': 1,
          'exercises_matched': ['Bench Press (Barbell)', 'Running'],
        },
        batch: batch,
      );
      expect(preview.toMap(), {
        'source': 'strong',
        'workoutsFound': 3,
        'workoutsAlreadyImported': 1,
        'workoutsEnriched': 1,
        'workoutsDropped': 0,
        'setsFound': 6,
        'setsEnriched': 2,
        'restTimersSet': 1,
        'setsDropped': 0,
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
