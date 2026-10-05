import 'package:heart/models/changes.dart';
import 'package:heart/models/errors.dart';
import 'package:test/test.dart';

void main() {
  group('ChangeCursor', () {
    test('round-trips through its opaque form, microseconds included', () {
      final cursor = ChangeCursor(
        at: DateTime.utc(2026, 10, 5, 1, 2, 3, 4, 5),
        id: '019a0000-0000-7000-8000-000000000001',
      );
      final back = ChangeCursor.parse(cursor.toString());
      expect(back.at, cursor.at);
      expect(back.id, cursor.id);
      expect(cursor.toString(), isNot(contains('=')));
    });

    test('anything else is a 400, never a fresh start', () {
      for (final raw in ['', 'nope', 'MjAyNi0xMC0wNQ', 'bm90fGFjdXJzb3I']) {
        expect(() => ChangeCursor.parse(raw), throwsA(isA<BadRequest>()), reason: raw);
      }
    });
  });
}
