import 'dart:convert';
import 'dart:io';

import 'package:heart_models/heart_models.dart';
import 'package:test/test.dart';

/// Pins the write side (api/bin/publish_library.dart, via the same query
/// `GET /v1/exercises` uses) against the read side (this package's [Exercise]
/// model): `test/fixtures/exercise_library_es_ES.json` is a real CDN locale
/// file, and every entry in it must parse. A key rename or dropped field on
/// either side breaks this test instead of failing silently as a missing
/// field reading as a default.
///
/// Test-only fixture: no `heart_models` version bump.
void main() {
  test('every exercise in the CDN es_ES fixture round-trips through Exercise.fromJson', () {
    final raw = File('test/fixtures/exercise_library_es_ES.json').readAsStringSync();
    final body = jsonDecode(raw) as Map<String, dynamic>;
    final entries = body['exercises'] as List;

    expect(entries, isNotEmpty);

    for (final entry in entries.cast<Map<String, dynamic>>()) {
      final exercise = Exercise.fromJson(entry);

      expect(exercise.id, entry['id']);
      expect(exercise.key, entry['key']);
      expect(exercise.name, isNotEmpty);
      // the library view: no signed-in caller, so nothing here is "mine"
      expect(exercise.isMine, isFalse);
    }
  });
}
