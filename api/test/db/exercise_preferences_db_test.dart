@Tags(['db'])
library;

import 'package:heart/models/errors.dart';
import 'package:heart_models/heart_models.dart';
import 'package:test/test.dart';

import 'db_test_utility.dart';

/// Integration coverage of the `ExercisePreferenceService` query strings against
/// a live Postgres: the per-(user, exercise) upsert and the per-field clear,
/// plus the COALESCE-merge and owner-scoping the SQL encodes.
///
/// Tagged `db` — skipped by the default `dart test`. Run with:
///   dart test --run-skipped -t db
void main() {
  final h = _Harness();

  late String ownerId;
  late String otherId; // a second user, to prove prefs are owner-scoped

  setUpAll(() async {
    await h.setupDatabase();
    ownerId = await h.seedProfile();
    otherId = await h.seedProfile();
  });

  tearDownAll(h.teardownDatabase);

  /// The stored `(unit_system, rest_timer)` row for [userId]/[exerciseId], or
  /// null when no preference exists. Reads the table directly so assertions see
  /// exactly what the upsert/clear wrote.
  Future<Map<String, dynamic>?> readPref(String userId, String exerciseId) async {
    final rows = await h.exec(
      'SELECT unit_system, rest_timer, note FROM exercise_preferences '
      'WHERE user_id = @u AND exercise_id = @e::uuid',
      {'u': userId, 'e': exerciseId},
    );
    return rows.isEmpty ? null : rows.first.toColumnMap();
  }

  group('savePreference — unreferenceable exercise ids (heart-api#74)', () {
    test('a nonexistent exercise id is NotFound(unknown_exercise), not a raw DB error', () async {
      // A well-formed uuid the FK cannot satisfy. Before the fix this escaped
      // the pool as a 23503 and the route answered 500.
      const ghost = '01a07dfe-0bf2-7d18-a1fa-79abe2a92472';
      final pref = ExercisePreference(exerciseId: ghost, unitSystem: MeasurementUnit.metric);

      await expectLater(
        h.db.savePreference(pref, ownerId),
        throwsA(
          isA<NotFound>()
              .having((e) => e.code, 'code', 'unknown_exercise')
              .having((e) => e.statusCode, 'statusCode', 404),
        ),
      );
    });

    test('another user’s private custom is refused identically — existence is not leaked', () async {
      final theirs = await h.insertId(
        'INSERT INTO exercises (name, category, target, user_id) VALUES (@n, @c, @t, @u) RETURNING id',
        {'n': h.uniqueName('Private'), 'c': 'Barbell', 't': 'Chest', 'u': otherId},
      );
      final pref = ExercisePreference(exerciseId: theirs, unitSystem: MeasurementUnit.metric);

      // Same code and status as the nonexistent id above: the response must not
      // let the caller tell "not yours" from "not there".
      await expectLater(
        h.db.savePreference(pref, ownerId),
        throwsA(isA<NotFound>().having((e) => e.code, 'code', 'unknown_exercise')),
      );

      // And nothing was written for either account.
      expect(await readPref(ownerId, theirs), isNull);
      expect(await readPref(otherId, theirs), isNull);
    });

    test('the caller’s own custom is accepted', () async {
      final mine = await h.insertId(
        'INSERT INTO exercises (name, category, target, user_id) VALUES (@n, @c, @t, @u) RETURNING id',
        {'n': h.uniqueName('Mine'), 'c': 'Barbell', 't': 'Back', 'u': ownerId},
      );

      final saved = await h.db.savePreference(
        ExercisePreference(exerciseId: mine, restTimer: 120),
        ownerId,
      );

      expect(saved.exerciseId, mine);
      expect(saved.restTimer, 120);
      expect((await readPref(ownerId, mine))?['rest_timer'], 120);
    });

    test('a shared library exercise is accepted', () async {
      final global = await h.seedGlobalExercise();

      final saved = await h.db.savePreference(
        ExercisePreference(exerciseId: global, unitSystem: MeasurementUnit.imperial),
        ownerId,
      );

      expect(saved.exerciseId, global);
      expect(saved.unitSystem, MeasurementUnit.imperial);
    });

    test('the returned preference is the merged row, not the request', () async {
      final global = await h.seedGlobalExercise();
      await h.db.savePreference(
        ExercisePreference(exerciseId: global, unitSystem: MeasurementUnit.metric, restTimer: 60),
        ownerId,
      );

      // Writing only the timer COALESCEs the unit through, so the response has
      // to report the stored state rather than echoing the partial request.
      final merged = await h.db.savePreference(
        ExercisePreference(exerciseId: global, restTimer: 45),
        ownerId,
      );

      expect(merged.restTimer, 45);
      expect(merged.unitSystem, MeasurementUnit.metric);
    });
  });

  group('savePreference', () {
    test('inserts both fields and returns the given preference', () async {
      final exerciseId = await h.seedGlobalExercise();
      final pref = ExercisePreference(
        exerciseId: exerciseId,
        unitSystem: MeasurementUnit.metric,
        restTimer: 90,
      );

      final saved = await h.db.savePreference(pref, ownerId);

      expect(saved.exerciseId, exerciseId);
      expect(saved.unitSystem, MeasurementUnit.metric);
      expect(saved.restTimer, 90);

      final row = await readPref(ownerId, exerciseId);
      expect(row, isNotNull);
      expect(row!['unit_system'], 'metric');
      expect(row['rest_timer'], 90);
    });

    test('surfaces through getExercises for the owning user only', () async {
      final exerciseId = await h.seedGlobalExercise();
      await h.db.savePreference(
        ExercisePreference(exerciseId: exerciseId, unitSystem: MeasurementUnit.imperial, restTimer: 45),
        ownerId,
      );

      final mine = await h.db.getExercises(ownerId);
      final ownRow = (mine['exercises'] as List).cast<Map>().firstWhere((e) => e['id'].toString() == exerciseId);
      expect(ownRow['unit_system'], 'imperial');
      expect(ownRow['rest_timer'], 45);

      // The same global exercise carries no preference for a different user.
      final theirs = await h.db.getExercises(otherId);
      final otherRow = (theirs['exercises'] as List).cast<Map>().firstWhere((e) => e['id'].toString() == exerciseId);
      expect(otherRow['unit_system'], isNull);
      expect(otherRow['rest_timer'], isNull);
    });

    test('upsert overrides an existing field with a new non-null value', () async {
      final exerciseId = await h.seedGlobalExercise();
      await h.db.savePreference(
        ExercisePreference(exerciseId: exerciseId, unitSystem: MeasurementUnit.metric, restTimer: 60),
        ownerId,
      );

      await h.db.savePreference(
        ExercisePreference(exerciseId: exerciseId, unitSystem: MeasurementUnit.imperial, restTimer: 120),
        ownerId,
      );

      final row = await readPref(ownerId, exerciseId);
      expect(row!['unit_system'], 'imperial');
      expect(row['rest_timer'], 120);
    });

    test('upsert preserves existing fields the new preference omits (COALESCE merge)', () async {
      final exerciseId = await h.seedGlobalExercise();
      await h.db.savePreference(
        ExercisePreference(exerciseId: exerciseId, unitSystem: MeasurementUnit.metric, restTimer: 75),
        ownerId,
      );

      // Only rest_timer supplied — the null unit_system must not wipe the stored one.
      await h.db.savePreference(
        ExercisePreference(exerciseId: exerciseId, restTimer: 30),
        ownerId,
      );

      final row = await readPref(ownerId, exerciseId);
      expect(row!['unit_system'], 'metric'); // preserved
      expect(row['rest_timer'], 30); // updated
    });

    test('pins a note on its own, with no unit or timer', () async {
      final exerciseId = await h.seedGlobalExercise();
      final saved = await h.db.savePreference(
        ExercisePreference(exerciseId: exerciseId, note: 'pause at the bottom'),
        ownerId,
      );

      expect(saved.note, 'pause at the bottom');
      final row = await readPref(ownerId, exerciseId);
      expect(row!['note'], 'pause at the bottom');
      expect(row['unit_system'], isNull);
      expect(row['rest_timer'], isNull);
    });

    test('a note-only upsert preserves a stored unit and timer', () async {
      final exerciseId = await h.seedGlobalExercise();
      await h.db.savePreference(
        ExercisePreference(exerciseId: exerciseId, unitSystem: MeasurementUnit.metric, restTimer: 75),
        ownerId,
      );

      await h.db.savePreference(ExercisePreference(exerciseId: exerciseId, note: 'one hand at a time'), ownerId);

      final row = await readPref(ownerId, exerciseId);
      expect(row!['unit_system'], 'metric');
      expect(row['rest_timer'], 75);
      expect(row['note'], 'one hand at a time');
    });

    test('a unit-only upsert preserves a pinned note', () async {
      final exerciseId = await h.seedGlobalExercise();
      await h.db.savePreference(ExercisePreference(exerciseId: exerciseId, note: 'keep me'), ownerId);

      await h.db.savePreference(
        ExercisePreference(exerciseId: exerciseId, unitSystem: MeasurementUnit.imperial),
        ownerId,
      );

      final row = await readPref(ownerId, exerciseId);
      expect(row!['note'], 'keep me');
      expect(row['unit_system'], 'imperial');
    });

    test('re-pinning replaces the note', () async {
      final exerciseId = await h.seedGlobalExercise();
      await h.db.savePreference(ExercisePreference(exerciseId: exerciseId, note: 'first'), ownerId);
      await h.db.savePreference(ExercisePreference(exerciseId: exerciseId, note: 'second'), ownerId);

      expect((await readPref(ownerId, exerciseId))!['note'], 'second');
    });
  });

  group('getExercisePreferences', () {
    test('lists unit-only, timer-only, and both rows, excluding chart-only and other users', () async {
      // A profile of this test's own: `ownerId` is shared file-wide and the
      // savePreference tests above leave rows behind for it, so a count
      // against it depends on test order.
      final listOwner = await h.seedProfile();
      final unitOnly = await h.seedGlobalExercise();
      final timerOnly = await h.seedGlobalExercise();
      final both = await h.seedGlobalExercise();
      final chartOnly = await h.seedGlobalExercise();
      final otherUsersExercise = await h.seedGlobalExercise();

      await h.db.savePreference(
        ExercisePreference(exerciseId: unitOnly, unitSystem: MeasurementUnit.imperial),
        listOwner,
      );
      await h.db.savePreference(
        ExercisePreference(exerciseId: timerOnly, restTimer: 60),
        listOwner,
      );
      await h.db.savePreference(
        ExercisePreference(exerciseId: both, unitSystem: MeasurementUnit.metric, restTimer: 90),
        listOwner,
      );
      await h.db.saveChartPreference(
        ChartPreference.create(id: chartOnly, type: ChartPreferenceType.totalVolume),
        listOwner,
      );
      await h.db.savePreference(
        ExercisePreference(exerciseId: otherUsersExercise, unitSystem: MeasurementUnit.imperial),
        otherId,
      );

      final prefs = (await h.db.getExercisePreferences(listOwner)).toList();

      expect(prefs, hasLength(3));
      expect(prefs.map((p) => p.exerciseId), isNot(contains(chartOnly)));
      expect(prefs.map((p) => p.exerciseId), isNot(contains(otherUsersExercise)));

      final unitOnlyPref = prefs.firstWhere((p) => p.exerciseId == unitOnly);
      expect(unitOnlyPref.unitSystem, MeasurementUnit.imperial);
      expect(unitOnlyPref.restTimer, isNull);

      final timerOnlyPref = prefs.firstWhere((p) => p.exerciseId == timerOnly);
      expect(timerOnlyPref.unitSystem, isNull);
      expect(timerOnlyPref.restTimer, 60);

      final bothPref = prefs.firstWhere((p) => p.exerciseId == both);
      expect(bothPref.unitSystem, MeasurementUnit.metric);
      expect(bothPref.restTimer, 90);
    });

    test('a note-only row is listed — the filter would otherwise hide the pin', () async {
      final noteOwner = await h.seedProfile();
      final exerciseId = await h.seedGlobalExercise();
      await h.db.savePreference(ExercisePreference(exerciseId: exerciseId, note: 'pause at the bottom'), noteOwner);

      final prefs = await h.db.getExercisePreferences(noteOwner);

      expect(prefs, hasLength(1));
      expect(prefs.first.exerciseId, exerciseId);
      expect(prefs.first.note, 'pause at the bottom');
      expect(prefs.first.unitSystem, isNull);
      expect(prefs.first.restTimer, isNull);
    });

    test('returns an empty list for a user with no preferences', () async {
      final freshUser = await h.seedProfile();
      expect(await h.db.getExercisePreferences(freshUser), isEmpty);
    });
  });

  group('clearPreference', () {
    test('unitSystem clears only the unit, leaving the rest timer intact', () async {
      final exerciseId = await h.seedGlobalExercise();
      await h.db.savePreference(
        ExercisePreference(exerciseId: exerciseId, unitSystem: MeasurementUnit.metric, restTimer: 90),
        ownerId,
      );

      await h.db.clearPreference(exerciseId, ownerId, ExercisePreferenceField.unitSystem);

      final row = await readPref(ownerId, exerciseId);
      expect(row!['unit_system'], isNull);
      expect(row['rest_timer'], 90);
    });

    test('restTimer clears only the timer, leaving the unit intact', () async {
      final exerciseId = await h.seedGlobalExercise();
      await h.db.savePreference(
        ExercisePreference(exerciseId: exerciseId, unitSystem: MeasurementUnit.imperial, restTimer: 90),
        ownerId,
      );

      await h.db.clearPreference(exerciseId, ownerId, ExercisePreferenceField.restTimer);

      final row = await readPref(ownerId, exerciseId);
      expect(row!['unit_system'], 'imperial');
      expect(row['rest_timer'], isNull);
    });

    test('note unpins only the note, leaving the unit and timer intact', () async {
      final exerciseId = await h.seedGlobalExercise();
      await h.db.savePreference(
        ExercisePreference(
          exerciseId: exerciseId,
          unitSystem: MeasurementUnit.metric,
          restTimer: 90,
          note: 'pause at the bottom',
        ),
        ownerId,
      );

      await h.db.clearPreference(exerciseId, ownerId, ExercisePreferenceField.note);

      final row = await readPref(ownerId, exerciseId);
      expect(row!['note'], isNull);
      expect(row['unit_system'], 'metric');
      expect(row['rest_timer'], 90);
    });

    test('unpinning leaves the row, so a later re-pin is an update', () async {
      final exerciseId = await h.seedGlobalExercise();
      await h.db.savePreference(ExercisePreference(exerciseId: exerciseId, note: 'gone'), ownerId);
      await h.db.clearPreference(exerciseId, ownerId, ExercisePreferenceField.note);

      expect(await readPref(ownerId, exerciseId), isNotNull, reason: 'the row survives an unpin');

      await h.db.savePreference(ExercisePreference(exerciseId: exerciseId, note: 'back'), ownerId);
      expect((await readPref(ownerId, exerciseId))!['note'], 'back');
    });

    test('is a no-op when no preference row exists', () async {
      final exerciseId = await h.seedGlobalExercise();
      // Nothing saved for this (user, exercise); clearing must not throw.
      await h.db.clearPreference(exerciseId, ownerId, ExercisePreferenceField.unitSystem);
      expect(await readPref(ownerId, exerciseId), isNull);
    });

    test('is scoped to the owner — another user cannot clear it', () async {
      final exerciseId = await h.seedGlobalExercise();
      await h.db.savePreference(
        ExercisePreference(exerciseId: exerciseId, unitSystem: MeasurementUnit.metric, restTimer: 90),
        ownerId,
      );

      // A different user clearing the same exercise touches no rows.
      await h.db.clearPreference(exerciseId, otherId, ExercisePreferenceField.unitSystem);

      final row = await readPref(ownerId, exerciseId);
      expect(row!['unit_system'], 'metric'); // owner's pref untouched
      expect(row['rest_timer'], 90);
    });
  });
}

class _Harness extends DatabaseTestBase;
