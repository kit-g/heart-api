import 'package:heart/globals/globals.dart';
import 'package:heart/inputs/inputs.dart';
import 'package:heart/models/errors.dart';
import 'package:heart_models/heart_models.dart';
import 'package:relic_core/relic_core.dart';
import 'package:test/test.dart';

import '../helpers/request.dart';

void main() {
  group('ConnectionCreateIn — self-check / parsed enums', () {
    Future<ConnectionCreateIn> parse(Map<String, dynamic> body) =>
        ConnectionCreateIn.fromRequest(jsonRequest(body: body)..user = User(id: 'u1'));

    const valid = {'targetId': 't1', 'role': 'COACH', 'domain': 'fitness'};

    test('parses targetId / role / domain', () async {
      final input = await parse(valid);
      expect(input.targetId, 't1');
      expect(input.role, ConnectionRole.coach);
      expect(input.domain, ConnectionDomain.fitness);
    });

    test('rejects connecting to yourself', () async {
      await expectLater(parse({...valid, 'targetId': 'u1'}), throwsA(isA<BadRequest>()));
    });

    test('rejects an unknown role', () async {
      await expectLater(parse({...valid, 'role': 'SENSEI'}), throwsA(isA<BadRequest>()));
    });

    test('rejects an unknown domain', () async {
      await expectLater(parse({...valid, 'domain': 'yoga'}), throwsA(isA<BadRequest>()));
    });

    test('rejects a missing targetId', () async {
      await expectLater(parse({'role': 'PEER', 'domain': 'fitness'}), throwsA(isA<BadRequest>()));
    });
  });

  group('ConnectionStatusIn — parsed enum', () {
    Future<ConnectionStatusIn> parse(Map<String, dynamic> body) =>
        ConnectionStatusIn.fromRequest(jsonRequest(body: body));

    test('parses a known status', () async {
      expect((await parse({'status': 'active'})).status, ConnectionStatus.active);
    });

    test('rejects an unknown status', () async {
      await expectLater(parse({'status': 'nonsense'}), throwsA(isA<BadRequest>()));
    });

    test('rejects a missing status', () async {
      await expectLater(parse({}), throwsA(isA<BadRequest>()));
    });
  });

  group('ConnectionListQuery — optional role filter', () {
    ConnectionListQuery parse(Map<String, String> query) =>
        ConnectionListQuery.fromRequest(bareRequest(method: Method.get, query: query));

    test('role is null when absent', () {
      expect(parse({}).role, isNull);
    });

    test('parses the role filter', () {
      expect(parse({'role': 'COACH'}).role, ConnectionRole.coach);
    });

    test('rejects an unknown role', () {
      expect(() => parse({'role': 'SENSEI'}), throwsA(isA<BadRequest>()));
    });
  });

  group('ConnectionRef.parse — composite id', () {
    test('splits <targetId>|<ROLE>|<domain>', () {
      final ref = ConnectionRef.parse('t1|COACH|fitness');
      expect(ref.targetId, 't1');
      expect(ref.role, ConnectionRole.coach);
      expect(ref.domain, ConnectionDomain.fitness);
    });

    for (final malformed in ['not-a-valid-id', 't1|COACH', 't1|COACH|fitness|extra']) {
      test('rejects the malformed id "$malformed" with BadRequest', () {
        expect(() => ConnectionRef.parse(malformed), throwsA(isA<BadRequest>()));
      });
    }
  });
}
