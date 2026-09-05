@Tags(['db'])
library;

import 'dart:convert';

import 'package:heart/publish/exercise_library.dart';
import 'package:test/test.dart';

import 'db_test_utility.dart';

/// Proves the CDN generator's fallback ladder on the actual rendered file,
/// not on the query alone (that's `exercises_db_test.dart`'s job): a real
/// `renderLibraryPublication` run against seeded translations must show the
/// Castilian overlay where one exists and fall through to base Spanish or
/// English otherwise.
///
/// Tagged `db` — skipped by the default `dart test`. Run with:
///   dart test --run-skipped -t db
void main() {
  final h = _Harness();

  Map<String, dynamic>? findEx(List<dynamic> list, String id) {
    for (final e in list) {
      final m = e as Map<String, dynamic>;
      if (m['id'] == id) return m;
    }
    return null;
  }

  setUpAll(h.setupDatabase);

  tearDownAll(h.teardownDatabase);

  test('es_ES.json shows the Castilian overlay where it exists, base Spanish or English otherwise', () async {
    final overlaid = await h.seedGlobalExercise();
    await h.exec(
      "INSERT INTO exercise_translations (exercise_id, locale, name, instructions) VALUES (@id::uuid, 'es', @n, @i)",
      {'id': overlaid, 'n': 'Sentadilla', 'i': 'Instrucciones neutras'},
    );
    await h.exec(
      "INSERT INTO exercise_translations (exercise_id, locale, name) VALUES (@id::uuid, 'es_ES', @n)",
      {'id': overlaid, 'n': 'Sentadilla castellana'},
    );

    final baseOnly = await h.seedGlobalExercise();
    await h.exec(
      "INSERT INTO exercise_translations (exercise_id, locale, name, instructions) VALUES (@id::uuid, 'es', @n, @i)",
      {'id': baseOnly, 'n': 'Peso muerto', 'i': 'Instrucciones base'},
    );

    final untranslatedName = h.uniqueName('English Only');
    final untranslated = await h.seedGlobalExercise(name: untranslatedName);

    final publication = await renderLibraryPublication(
      service: h.db,
      locales: const ['en', 'es', 'es_ES'],
      version: 'test',
      generatedAt: DateTime.utc(2026),
    );

    final esEs = (jsonDecode(publication.localeFiles['es_ES']!) as Map<String, dynamic>)['exercises'] as List;

    final overlaidRow = findEx(esEs, overlaid);
    expect(overlaidRow, isNotNull);
    expect(overlaidRow!['name'], 'Sentadilla castellana');
    // a field missing from the es_ES row still reads from the base language,
    // not straight to English — the per-field ladder, proven on the file.
    expect(overlaidRow['instructions'], 'Instrucciones neutras');

    final baseOnlyRow = findEx(esEs, baseOnly);
    expect(baseOnlyRow, isNotNull);
    expect(baseOnlyRow!['name'], 'Peso muerto');
    expect(baseOnlyRow['instructions'], 'Instrucciones base');

    final untranslatedRow = findEx(esEs, untranslated);
    expect(untranslatedRow, isNotNull);
    expect(untranslatedRow!['name'], untranslatedName);
  });

  test('every row is a library row: own is false and no per-user preference leaks through', () async {
    final id = await h.seedGlobalExercise();

    final publication = await renderLibraryPublication(
      service: h.db,
      locales: const ['en'],
      version: 'test',
      generatedAt: DateTime.utc(2026),
    );

    final en = (jsonDecode(publication.localeFiles['en']!) as Map<String, dynamic>)['exercises'] as List;
    final row = findEx(en, id);
    expect(row, isNotNull);
    expect(row!['own'], isFalse);
    expect(row['unit_system'], isNull);
    expect(row['rest_timer'], isNull);
  });
}

class _Harness extends DatabaseTestBase;
