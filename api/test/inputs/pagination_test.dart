import 'package:heart/inputs/inputs.dart';
import 'package:heart/models/errors.dart';
import 'package:relic_core/relic_core.dart';
import 'package:test/test.dart';

import '../helpers/request.dart';

void main() {
  group('PageQuery — integer / stringOrNull', () {
    PageQuery parse({Map<String, String> query = const {}, int defaultLimit = 30, int maxLimit = 100}) =>
        PageQuery.fromRequest(
          bareRequest(method: Method.get, query: query),
          defaultLimit: defaultLimit,
          maxLimit: maxLimit,
        );

    test('defaults the limit and leaves the cursor null when absent', () {
      final q = parse();
      expect(q.limit, 30);
      expect(q.cursor, isNull);
    });

    test('honours the defaultLimit override', () => expect(parse(defaultLimit: 20).limit, 20));

    test('clamps above max and below min', () {
      expect(parse(query: {'limit': '9999'}).limit, 100);
      expect(parse(query: {'limit': '0'}).limit, 1);
    });

    test('reads an explicit cursor + limit', () {
      final q = parse(query: {'limit': '25', 'cursor': 'abc'});
      expect(q.limit, 25);
      expect(q.cursor, 'abc');
    });

    test('treats an empty cursor as absent', () => expect(parse(query: {'cursor': ''}).cursor, isNull));

    test('rejects a non-integer limit', () {
      expect(() => parse(query: {'limit': 'abc'}), throwsA(isA<BadRequest>()));
    });
  });
}
