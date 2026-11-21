import 'dart:convert';

import 'package:heart_models/heart_models.dart';
import 'package:test/test.dart';

ServerRefusal? _parse(int status, Object? body, {String method = 'POST', String route = '/v1/goals'}) {
  return ServerRefusal.tryParse(status: status, method: method, route: route, body: body);
}

void main() {
  group('ServerRefusal.tryParse', () {
    test('reads the code and keeps the rest of the body as details', () {
      final body = jsonDecode('{"error": "too many requests", "code": "rate_limited", "retryAfter": 30}');
      final refusal = _parse(429, body, method: 'GET')!;

      expect(refusal.status, 429);
      expect(refusal.code, 'rate_limited');
      expect(refusal.method, 'GET');
      expect(refusal.route, '/v1/goals');
      expect(refusal.details, {'error': 'too many requests', 'retryAfter': 30});
    });

    test('carries a code this build does not know as sent', () {
      final refusal = _parse(409, jsonDecode('{"code": "some_future_code", "newField": [1, 2]}'))!;

      expect(refusal.code, 'some_future_code');
      expect(refusal.details, {
        'newField': [1, 2],
      });
    });

    test('reads a body that is a plain Map, not Map<String, dynamic>', () {
      final body = Map<dynamic, dynamic>.of(jsonDecode('{"code": "goal_limit", "limit": 20}') as Map);
      final refusal = _parse(403, body)!;

      expect(refusal.code, 'goal_limit');
      expect(refusal.details, {'limit': 20});
    });

    test('a body without a code is not a refusal', () {
      expect(_parse(429, jsonDecode('{"message": "Too Many Requests"}')), isNull);
    });

    test('a code that is not a string is not a refusal', () {
      expect(_parse(400, {'code': 7}), isNull);
    });

    for (final body in [null, '', 'not found', <dynamic>[]]) {
      test('a body that is not a JSON object ("$body") is not a refusal', () {
        expect(_parse(404, body), isNull);
      });
    }

    for (final status in [400, 499]) {
      test('a $status with a code is a refusal', () {
        expect(_parse(status, {'code': 'x'})?.status, status);
      });
    }

    for (final status in [200, 399, 500, 503]) {
      test('a $status is not a refusal, even with a code', () {
        expect(_parse(status, {'error': 'server error', 'code': 'server_error'}), isNull);
      });
    }

    test('the top level of details cannot be changed', () {
      final refusal = _parse(403, {'code': 'goal_limit'})!;
      expect(() => refusal.details['code'] = 'other', throwsUnsupportedError);
    });
  });

  test('a refusal outside 4xx cannot be built', () {
    expect(
      () => ServerRefusal(status: 500, code: 'x', method: 'GET', route: '/v1/goals'),
      throwsA(isA<AssertionError>()),
    );
  });

  test('toString names the status, code, method and route, never the body', () {
    final body = jsonDecode('{"code": "name_taken", "error": "the name \\"my secret plan\\" is taken"}');
    final refusal = _parse(409, body, method: 'PUT', route: '/v1/templates/{id}')!;

    expect(refusal.toString(), 'ServerRefusal: 409 name_taken at PUT /v1/templates/{id}');
    expect(refusal.toString(), isNot(contains('secret')));
  });

  group('equality', () {
    ServerRefusal refusal({
      int status = 403,
      String code = 'goal_limit',
      String method = 'POST',
      String route = '/v1/goals',
      Map<String, dynamic> details = const {},
    }) => ServerRefusal(status: status, code: code, method: method, route: route, details: details);

    test('a parsed refusal equals the one built by hand, nested details included', () {
      final parsed = _parse(403, jsonDecode('{"code": "goal_limit", "limit": {"max": 10, "kinds": ["a", "b"]}}'));
      final built = refusal(
        details: {
          'limit': {
            'max': 10,
            'kinds': ['a', 'b'],
          },
        },
      );

      expect(parsed, built);
      expect(parsed.hashCode, built.hashCode);
    });

    test('any differing field makes refusals unequal', () {
      const kinds = {
        'kinds': ['a'],
      };
      final base = refusal(details: kinds);

      expect(base, isNot(refusal(status: 409, details: kinds)));
      expect(base, isNot(refusal(code: 'other', details: kinds)));
      expect(base, isNot(refusal(method: 'GET', details: kinds)));
      expect(base, isNot(refusal(route: '/v1/goals/{id}', details: kinds)));
      expect(
        base,
        isNot(
          refusal(
            details: {
              'kinds': ['b'],
            },
          ),
        ),
      );
      expect(
        base,
        isNot(
          refusal(
            details: {
              'kinds': ['a', 'b'],
            },
          ),
        ),
      );
      expect(
        base,
        isNot(
          refusal(
            details: {
              'other': ['a'],
            },
          ),
        ),
      );
    });
  });
}
