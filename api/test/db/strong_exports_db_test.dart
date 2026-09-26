@Tags(['db'])
library;

import 'dart:io';

import 'package:heart/models/imports.dart';
import 'package:test/test.dart';

import 'db_test_utility.dart';

/// Re-import against one real history exported four ways: Strong's export has
/// two switches — rest timers, notes — and `content/assets/exports/strong`
/// holds every combination. Whatever order they arrive in, the history must
/// end up exactly as if the complete export had been imported once, and a
/// poorer export must never take anything away.
///
/// The exports are the owner's real history and `content/assets/` is
/// gitignored, so this suite runs where they exist (the owner's machine) and
/// skips everywhere else, CI included.
///
/// Tagged `db` — skipped by the default `dart test`. Run with:
///   dart test --run-skipped -t db
void main() {
  final h = _Harness();

  const dir = '../content/assets/exports/strong';
  final exports = {
    'bare': '$dir/strong_workouts.csv',
    'timers': '$dir/strong_workouts 2.csv',
    'notes': '$dir/strong_workouts 3.csv',
    'full': '$dir/strong_workouts 4.csv',
  };
  final present = exports.values.every((path) => File(path).existsSync());
  late Map<String, WorkoutImport> batches;
  final profiles = <String>[];

  Future<String> profile() async {
    final id = await h.seedProfile();
    profiles.add(id);
    return id;
  }

  Future<WorkoutImportReport> import(String owner, String export) =>
      h.db.importWorkouts(userId: owner, batch: batches[export]!);

  /// Everything an import can write, in a stable order, free of ids and
  /// timestamps minted per account.
  Future<List<Map<String, dynamic>>> history(String owner) async {
    final rows = await h.exec(
      'SELECT w.import_id, w.note AS workout_note, we.exercise_order, e.name, we.note AS exercise_note, '
      '       es.set_order, es.weight, es.reps, es.duration, es.distance, es.set_type, es.rpe '
      'FROM workouts w '
      'JOIN workout_exercises we ON we.workout_id = w.id '
      'JOIN exercises e ON e.id = we.exercise_id '
      'LEFT JOIN exercise_sets es ON es.workout_exercise_id = we.id '
      'WHERE w.user_id = @id '
      'ORDER BY w.import_id, we.exercise_order, es.set_order',
      {'id': owner},
    );
    return [for (final r in rows) r.toColumnMap()];
  }

  Future<Map<String, int?>> restTimers(String owner) async {
    final rows = await h.exec(
      'SELECT e.name, ep.rest_timer FROM exercise_preferences ep JOIN exercises e ON e.id = ep.exercise_id '
      'WHERE ep.user_id = @id',
      {'id': owner},
    );
    return {for (final r in rows) r.toColumnMap()['name'] as String: r.toColumnMap()['rest_timer'] as int?};
  }

  late List<Map<String, dynamic>> reference;
  late Map<String, int?> referenceTimers;

  // `make test-api-db` passes --run-skipped (db tests are skip-tagged), which
  // would run a `skip:`ped group too — so the suite is only registered when
  // its files exist, and otherwise reports itself skipped at runtime.
  if (!present) {
    test('four exports of one Strong history', () {
      markTestSkipped('the Strong exports are not in $dir (content/assets is gitignored)');
    });
    return;
  }

  group(
    'four exports of one Strong history',
    () {
      setUpAll(() async {
        await h.setupDatabase();
        batches = {
          for (final MapEntry(key: name, value: path) in exports.entries)
            name: WorkoutImport.fromStrongCsv(File(path).readAsStringSync()),
        };
        final once = await profile();
        await import(once, 'full');
        reference = await history(once);
        referenceTimers = await restTimers(once);
      });

      tearDownAll(() async {
        await h.exec('DELETE FROM workouts WHERE user_id = ANY(@ids)', {'ids': profiles});
        await h.exec('DELETE FROM archive.deleted_workouts WHERE user_id = ANY(@ids)', {'ids': profiles});
        await h.teardownDatabase();
      });

      test('the four exports are one history: same workouts, same sets', () {
        final identities = {for (final b in batches.values) b.workouts.map((w) => w.importId).join(',')};
        expect(identities, hasLength(1));
        final sets = {for (final b in batches.values) b.setsFound};
        expect(sets, hasLength(1));
        expect(batches.values.map((b) => b.rowsSkipped), everyElement(0));
      });

      test('the complete export lands everything it carries', () async {
        final typed = reference.where((r) => r['set_type'] != null).map((r) => r['set_type']);
        expect(typed.where((t) => t == 'w'), hasLength(45));
        expect(typed.where((t) => t == 'd'), hasLength(59));
        expect(typed.where((t) => t == 'f'), hasLength(1));
        final exerciseNotes = {
          for (final r in reference) '${r['import_id']}/${r['exercise_order']}': r['exercise_note'],
        }..removeWhere((_, note) => note == null);
        expect(exerciseNotes, hasLength(14));
        expect(reference.map((r) => r['workout_note']).whereType<String>().toSet(), {'We’re'});
        expect(referenceTimers, isNotEmpty);
      });

      for (final order in const [
        ['bare', 'timers', 'notes', 'full'],
        ['bare', 'notes', 'timers'],
        ['timers', 'notes'],
        ['notes', 'timers'],
        ['bare', 'full'],
        ['full', 'notes', 'timers', 'bare'],
      ]) {
        test('importing ${order.join(' → ')} ends exactly where the complete export does', () async {
          final owner = await profile();
          for (final export in order) {
            await import(owner, export);
          }
          expect(await history(owner), reference);
          expect(await restTimers(owner), referenceTimers);
        });
      }

      test('each step reports what it did', () async {
        final owner = await profile();
        final found = batches['full']!.workouts.length;

        final bare = await import(owner, 'bare');
        expect(bare.workoutsCreated, found);
        expect(bare.restTimersSet, 0);

        // timers only: no field on a workout or set changes
        final timers = await import(owner, 'timers');
        expect(timers.workoutsCreated, 0);
        expect(timers.workoutsEnriched, 0);
        expect(timers.workoutsSkipped, found);
        expect(timers.restTimersSet, referenceTimers.length);

        // notes: the workouts carrying a note are enriched, the rest skipped
        final notes = await import(owner, 'notes');
        expect(notes.workoutsCreated, 0);
        expect(notes.workoutsEnriched, greaterThan(0));
        expect(notes.workoutsEnriched + notes.workoutsSkipped, found);
        expect(notes.setsEnriched, 0);
        expect(notes.restTimersSet, 0);

        // nothing left to add
        final full = await import(owner, 'full');
        expect(full.workoutsEnriched, 0);
        expect(full.workoutsSkipped, found);
        expect(full.restTimersSet, 0);
      });

      test('the preview of each step matches its commit', () async {
        final owner = await profile();
        await import(owner, 'bare');
        for (final export in ['timers', 'notes', 'full']) {
          final preview = await h.db.previewImport(userId: owner, batch: batches[export]!);
          final report = await import(owner, export);
          expect(
            [preview.workoutsEnriched, preview.setsEnriched, preview.restTimersSet],
            [report.workoutsEnriched, report.setsEnriched, report.restTimersSet],
            reason: export,
          );
        }
      });
    },
  );
}

class _Harness extends DatabaseTestBase;
