import 'dart:convert';
import 'dart:io';

import 'package:heart/models/imports.dart';
import 'package:test/test.dart';

/// The app's own CSV export (`ExportSnapshot.toCsv` in heart-of-yours):
/// `test/fixtures/heart/export.csv` is written by hand to the writer's rules —
/// workouts oldest first, ISO instants in UTC, 1-based `set_index` per
/// exercise, the unit per row in the unit the user saw (two exercises
/// overridden to imperial in a metric store), two decimals at most, RFC 4180
/// quoting, LF line ends — because no real file is in a bucket yet.
const _fixture = 'test/fixtures/heart/export.csv';

const _header = 'workout_id,start,end,exercise_id,exercise_name,set_index,weight,unit,reps,duration,distance,notes\n';

const _push = '019ca8d7-2d00-7b4a-8c5d-6e7f80910a01';
const _cardio = '019cb29a-90c0-7c5b-9d6e-7f8091a2b302';
const _carries = '019cbd70-9d00-7d6c-ae7f-8091a2b3c403';
const _bench = '019a4394-8c00-7a1e-8b2c-3d4e5f601001';
const _plank = '019a4394-8c00-7a1e-8b2c-3d4e5f601003';
const _muffin = '019c186e-2e80-7f3a-9c1d-2e3f4a5b6c7d';

String _row({
  String workout = _push,
  String start = '2026-03-01T10:00:00.000Z',
  String end = '2026-03-01T11:00:00.000Z',
  String exerciseId = _bench,
  String exercise = 'Bench Press (Barbell)',
  String index = '1',
  String weight = '',
  String unit = '',
  String reps = '',
  String duration = '',
  String distance = '',
  String notes = '',
}) => '$workout,$start,$end,$exerciseId,$exercise,$index,$weight,$unit,$reps,$duration,$distance,$notes\n';

void main() {
  group('WorkoutImport.fromHeartCsv', () {
    final batch = WorkoutImport.fromHeartCsv(File(_fixture).readAsStringSync());

    test('one workout per workout_id, in file order, without a name or a note', () {
      expect(batch.source, 'heart');
      expect(batch.workouts.map((w) => w.workoutId), [_push, _cardio, _carries]);
      expect(batch.workouts.map((w) => w.name), everyElement(isNull));
      expect(batch.workouts.map((w) => w.note), everyElement(isNull));
      expect(batch.rowsSkipped, 0);
      expect(batch.setsFound, 9);
    });

    test('the import id is the workout id, and the id itself travels in the payload', () {
      final push = batch.workouts.first;
      expect(push.importId, 'heart:$_push');
      expect(push.toPayload()['workoutId'], _push);
    });

    test('instants are read as written, in UTC', () {
      final push = batch.workouts.first;
      expect(push.start, DateTime.utc(2026, 3, 1, 10));
      expect(push.end, DateTime.utc(2026, 3, 1, 11));
      expect(batch.workouts[1].start, DateTime.utc(2026, 3, 3, 7, 30));
    });

    test('the same exercise logged twice stays two: a block opens where set_index restarts', () {
      final push = batch.workouts.first;
      expect(push.exercises.map((e) => e.name), [
        'Bench Press (Barbell)',
        'Muffin, "special" pull-up',
        'Bench Press (Barbell)',
      ]);
      expect(push.exercises.map((e) => e.sets.length), [2, 1, 1]);
    });

    test('weights and distances come back to kg and km from the unit each row names', () {
      final [bench, muffin, benchAgain] = batch.workouts.first.exercises;
      expect(bench.sets.map((s) => s.weight), [closeTo(60, 0.01), closeTo(62.5, 0.01)]);
      expect(bench.sets.map((s) => s.reps), [8, 6]);
      expect(muffin.sets.single.reps, 10);
      expect(muffin.sets.single.weight, isNull);
      expect(benchAgain.sets.single.weight, closeTo(50, 0.01));

      final [run, plank] = batch.workouts[1].exercises;
      expect(run.sets.single.distance, closeTo(5, 0.01));
      expect(run.sets.single.duration, 1500);
      expect(plank.sets.single.duration, 60);
      expect(plank.sets.single.weight, isNull);
    });

    test('a carry names both units, weight\'s first', () {
      final [walk, plank] = batch.workouts.last.exercises;
      expect(walk.sets.map((s) => (s.weight, s.distance, s.duration)), [(40, 0.05, null), (40, 0.05, 30)]);
      expect(plank.sets.single.weight, 10);
      expect(plank.sets.single.duration, 45);
    });

    test('notes is the exercise note, kept once, line breaks included', () {
      expect(batch.workouts.first.exercises[1].note, 'one hand at a time');
      expect(batch.workouts[1].exercises[1].note, 'Held it,\nbarely');
      expect(batch.workouts.last.exercises[1].note, isNull);
    });

    test('the file has no set types and no RPE', () {
      for (final workout in batch.workouts) {
        for (final exercise in workout.exercises) {
          expect(exercise.sets.map((s) => s.type), everyElement(isNull));
          expect(exercise.sets.map((s) => s.rpe), everyElement(isNull));
          expect(exercise.restTimers, isEmpty);
        }
      }
      expect(batch.restTimers, isEmpty);
    });

    test('each exercise carries the id the file names it by', () {
      final ids = {for (final e in batch.exercises) e['name']: e['exerciseId']};
      expect(ids, {
        'Bench Press (Barbell)': _bench,
        'Muffin, "special" pull-up': _muffin,
        'Run': '019a4394-8c00-7a1e-8b2c-3d4e5f601002',
        'Plank': _plank,
        "Farmer's Walk": '019a4394-8c00-7a1e-8b2c-3d4e5f601004',
      });
      final payload = jsonDecode(batch.toParams(userId: 'u1')['exercises'] as String) as List;
      expect(payload.first, containsPair('exerciseId', _bench));
    });

    test('a name the file gives two ids is matched by name alone', () {
      final twice = WorkoutImport.fromHeartCsv(
        '$_header'
        '${_row(reps: '5')}'
        '${_row(workout: _cardio, start: '2026-03-03T07:30:00.000Z', end: '', exerciseId: _plank, reps: '5')}',
      );
      expect(twice.exercises.single, isNot(contains('exerciseId')));
    });

    test('an exercise id that is not a UUID is no id', () {
      final local = WorkoutImport.fromHeartCsv('$_header${_row(exerciseId: 'ex-bench', reps: '5')}');
      expect(local.workouts.single.exercises.single.exerciseId, isNull);
      expect(local.exercises.single, isNot(contains('exerciseId')));
    });

    test('the request\'s unit and offset change nothing', () {
      final csv = File(_fixture).readAsStringSync();
      final asked = ImportSource.heart.parse(csv, unit: .imperial, utcOffset: const Duration(hours: -4));
      expect(asked.workouts.first.start, batch.workouts.first.start);
      expect(
        asked.workouts.first.exercises.first.sets.first.weight,
        batch.workouts.first.exercises.first.sets.first.weight,
      );
      expect(asked.workouts.last.exercises.first.sets.first.distance, 0.05);
    });
  });

  group('rows the parser refuses', () {
    test('a workout id that is not a UUID (a store older than UUIDs) still imports, under an opaque identity', () {
      final batch = WorkoutImport.fromHeartCsv(
        '$_header'
        '${_row(workout: '1700000000000', reps: '5')}'
        '${_row(workout: '', reps: '5')}'
        '${_row(reps: '5')}',
      );
      expect(batch.workouts, hasLength(2));
      final [old, current] = batch.workouts;
      expect(old.workoutId, isNull);
      expect(old.importId, startsWith('heart:'));
      expect(old.importId, isNot(contains('1700000000000')));
      expect(old.toPayload(), isNot(contains('workoutId')));
      expect(current.importId, 'heart:$_push');
      expect(batch.rowsSkipped, 1);
    });

    test('an upper-case id is the same identity', () {
      final batch = WorkoutImport.fromHeartCsv('$_header${_row(workout: _push.toUpperCase(), reps: '5')}');
      expect(batch.workouts.single.importId, 'heart:$_push');
    });

    test('a row with nothing measured, or with an unreadable start, is skipped and counted', () {
      final batch = WorkoutImport.fromHeartCsv(
        '$_header'
        '${_row()}'
        '${_row(workout: _cardio, start: 'yesterday', reps: '5')}'
        '${_row(index: '2', reps: '5')}',
      );
      expect(batch.workouts.single.exercises.single.sets, hasLength(1));
      expect(batch.rowsSkipped, 2);
    });

    test('an unreadable end costs the end, not the workout', () {
      final batch = WorkoutImport.fromHeartCsv('$_header${_row(end: 'later', reps: '5')}');
      expect(batch.workouts.single.end, isNull);
      expect(batch.rowsSkipped, 0);
    });

    test('zero reads as not recorded, as from the other exporters', () {
      final batch = WorkoutImport.fromHeartCsv('$_header${_row(weight: '0', unit: 'kg', reps: '5')}');
      final set = batch.workouts.single.exercises.single.sets.single;
      expect(set.weight, isNull);
      expect(set.reps, 5);
    });

    test('a skipped first set still opens its exercise\'s second block', () {
      final batch = WorkoutImport.fromHeartCsv(
        '$_header'
        '${_row(index: '1', reps: '5')}'
        '${_row(index: '2', reps: '5')}'
        '${_row(index: '1')}'
        '${_row(index: '2', reps: '3')}',
      );
      expect(batch.workouts.single.exercises.map((e) => e.sets.length), [2, 1]);
      expect(batch.rowsSkipped, 1);
    });

    test('an end before the start is not kept; one days later is, for anomaly review', () {
      final batch = WorkoutImport.fromHeartCsv(
        '$_header'
        '${_row(end: '2026-03-01T09:00:00.000Z', reps: '5')}'
        '${_row(workout: _cardio, start: '2026-03-03T07:30:00.000Z', end: '2026-03-05T07:30:00.000Z', reps: '5')}'
        '${_row(workout: _carries, start: '2026-03-05T10:00:00.000Z', end: '', reps: '5')}',
      );
      expect(batch.workouts.map((w) => w.end), [null, DateTime.utc(2026, 3, 5, 7, 30), null]);
    });

    test('a header alone is an empty batch, not a refusal', () {
      final batch = WorkoutImport.fromHeartCsv(_header);
      expect(batch.workouts, isEmpty);
      expect(batch.rowsSkipped, 0);
    });

    test('a file without the Heart columns is refused', () {
      expect(() => WorkoutImport.fromHeartCsv('a,b\n1,2\n'), throwsFormatException);
      expect(
        () => WorkoutImport.fromHeartCsv('Date,Workout Name,Exercise Name\n2023-01-15 17:35:12,Push,Squat\n'),
        throwsFormatException,
      );
    });
  });
}
