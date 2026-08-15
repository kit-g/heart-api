@Tags(['db'])
library;

import 'package:heart_models/heart_models.dart';
import 'package:test/test.dart';

import 'db_test_utility.dart';

/// Full integration coverage of the `ChartPreferenceService` query strings
/// against a live Postgres. Chart preferences live in the shared
/// `exercise_preferences` table: `saveChartPreference` upserts a per-(user,
/// exercise) `chart_type`, `getPreferences` reads back the rows whose
/// `chart_type` is set (owner-scoped), and `deleteChartPreference` nulls the
/// `chart_type` (owner-scoped) without removing the row.
///
/// Tagged `db` — skipped by the default `dart test`. Run with:
///   dart test --run-skipped -t db
void main() {
  final h = _Harness();

  /// A chart preference whose `id` is the exercise it targets (the shape
  /// `saveChartPreference` expects — it reads `preference.id!` as the
  /// exercise_id and `preference.type.value` as the chart_type).
  ChartPreference pref(String exerciseId, ChartPreferenceType type) =>
      ChartPreference.fromRow({'id': exerciseId, 'type': type.value});

  /// Inserts an `exercise_preferences` row directly so tests can control
  /// `chart_type` / `unit_system` / `created_at` (the harness has no helper for
  /// this table, and `saveChartPreference` can't set `created_at`).
  Future<void> insertPref(
    String userId,
    String exerciseId, {
    String? chartType,
    String? unitSystem,
    DateTime? createdAt,
  }) {
    return h.exec(
      'INSERT INTO exercise_preferences (user_id, exercise_id, chart_type, unit_system, created_at) '
      'VALUES (@u, @e::uuid, @c, @us, coalesce(@ca::timestamptz, now()))',
      {'u': userId, 'e': exerciseId, 'c': chartType, 'us': unitSystem, 'ca': createdAt},
    );
  }

  setUpAll(() async {
    await h.setupDatabase();
  });

  tearDownAll(h.teardownDatabase);

  group('getPreferences', () {
    test('returns the owner\'s chart preferences newest-first', () async {
      final owner = await h.seedProfile();
      final exOld = await h.seedGlobalExercise();
      final exNew = await h.seedGlobalExercise();
      // Explicit timestamps so the created_at DESC ordering is deterministic.
      await insertPref(
        owner,
        exOld,
        chartType: ChartPreferenceType.totalVolume.value,
        createdAt: DateTime.utc(2026, 1, 1),
      );
      await insertPref(
        owner,
        exNew,
        chartType: ChartPreferenceType.topSetWeight.value,
        createdAt: DateTime.utc(2026, 2, 1),
      );

      final prefs = (await h.db.getPreferences(owner)).toList();

      expect(prefs, hasLength(2));
      expect(prefs.first.id, exNew);
      expect(prefs.first.type, ChartPreferenceType.topSetWeight);
      expect(prefs.last.id, exOld);
      expect(prefs.last.type, ChartPreferenceType.totalVolume);
    });

    test('excludes rows whose chart_type is null (unit-only preference)', () async {
      final owner = await h.seedProfile();
      final charted = await h.seedGlobalExercise();
      final unitOnly = await h.seedGlobalExercise();
      await insertPref(owner, charted, chartType: ChartPreferenceType.totalReps.value);
      await insertPref(owner, unitOnly, unitSystem: 'metric'); // chart_type stays NULL

      final prefs = (await h.db.getPreferences(owner)).toList();

      expect(prefs, hasLength(1));
      expect(prefs.single.id, charted);
    });

    test('is scoped to the user and does not leak another user\'s preferences', () async {
      final owner = await h.seedProfile();
      final other = await h.seedProfile();
      final ex = await h.seedGlobalExercise();
      await insertPref(other, ex, chartType: ChartPreferenceType.totalVolume.value);

      expect(await h.db.getPreferences(owner), isEmpty);
    });
  });

  group('saveChartPreference', () {
    test('persists the preference and reads back through getPreferences', () async {
      final owner = await h.seedProfile();
      final ex = await h.seedGlobalExercise();

      final saved = await h.db.saveChartPreference(pref(ex, ChartPreferenceType.estimatedOneRepMax), owner);

      // The mixin echoes the input back unchanged.
      expect(saved.id, ex);
      expect(saved.type, ChartPreferenceType.estimatedOneRepMax);

      final prefs = (await h.db.getPreferences(owner)).toList();
      expect(prefs.single.id, ex);
      expect(prefs.single.type, ChartPreferenceType.estimatedOneRepMax);
    });

    test('upserts in place on a repeat save, updating chart_type without duplicating', () async {
      final owner = await h.seedProfile();
      final ex = await h.seedGlobalExercise();

      await h.db.saveChartPreference(pref(ex, ChartPreferenceType.totalVolume), owner);
      await h.db.saveChartPreference(pref(ex, ChartPreferenceType.averageWorkingWeight), owner);

      final prefs = (await h.db.getPreferences(owner)).toList();
      expect(prefs, hasLength(1)); // UNIQUE (user_id, exercise_id) — no second row
      expect(prefs.single.type, ChartPreferenceType.averageWorkingWeight);
    });
  });

  group('deleteChartPreference', () {
    test('clears the chart_type so the preference drops out of getPreferences', () async {
      final owner = await h.seedProfile();
      final ex = await h.seedGlobalExercise();
      await h.db.saveChartPreference(pref(ex, ChartPreferenceType.totalReps), owner);

      await h.db.deleteChartPreference(ex, owner);

      expect(await h.db.getPreferences(owner), isEmpty);
      // The row itself survives — delete only nulls chart_type.
      final rows = await h.exec(
        'SELECT chart_type FROM exercise_preferences WHERE user_id = @u AND exercise_id = @e::uuid',
        {'u': owner, 'e': ex},
      );
      expect(rows, hasLength(1));
      expect(rows.first.toColumnMap()['chart_type'], isNull);
    });

    test('is owner-scoped: deleting as another user leaves the preference intact', () async {
      final owner = await h.seedProfile();
      final other = await h.seedProfile();
      final ex = await h.seedGlobalExercise();
      await h.db.saveChartPreference(pref(ex, ChartPreferenceType.topSetWeight), owner);

      await h.db.deleteChartPreference(ex, other); // wrong user — no-op

      final prefs = (await h.db.getPreferences(owner)).toList();
      expect(prefs.single.type, ChartPreferenceType.topSetWeight);
    });

    test('deleting an unknown exercise id is a no-op', () async {
      final owner = await h.seedProfile();
      await expectLater(
        h.db.deleteChartPreference('00000000-0000-7000-8000-000000000000', owner),
        completes,
      );
    });
  });

  group('saveChartOrder', () {
    test('is not implemented', () async {
      final owner = await h.seedProfile();
      // Throws synchronously (it's a stub), so match on the invocation itself.
      expect(
        () => h.db.saveChartOrder(const ['a', 'b'], owner),
        throwsA(isA<UnimplementedError>()),
      );
    });
  });
}

class _Harness extends DatabaseTestBase;
