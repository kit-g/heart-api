@Tags(['db'])
library;

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
      'SELECT unit_system, rest_timer FROM exercise_preferences '
      'WHERE user_id = @u AND exercise_id = @e::uuid',
      {'u': userId, 'e': exerciseId},
    );
    return rows.isEmpty ? null : rows.first.toColumnMap();
  }

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
