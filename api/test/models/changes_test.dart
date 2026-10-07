import 'package:heart/models/changes.dart';
import 'package:heart/models/errors.dart';
import 'package:test/test.dart';

void main() {
  group('ChangeCursor', () {
    test('round-trips through its opaque form, a 64-bit transaction id included', () {
      const cursor = ChangeCursor(xid: '18446744073709551615', id: '019a0000-0000-7000-8000-000000000001');
      final back = ChangeCursor.parse(cursor.toString());
      expect(back.xid, cursor.xid);
      expect(back.id, cursor.id);
      expect(cursor.toString(), isNot(contains('=')));
    });

    test('anything else is a 400, never a fresh start', () {
      for (final raw in [
        '',
        'nope',
        'MjAyNi0xMC0wNQ',
        'bm90fGFjdXJzb3I',
        'MjAyNi0xMC0wNVQwMDowMDowMFp8MDE5YTAwMDAtMDAwMC03MDAwLTgwMDAtMDAwMDAwMDAwMDAx',
      ]) {
        expect(() => ChangeCursor.parse(raw), throwsA(isA<BadRequest>()), reason: raw);
      }
    });
  });
}
