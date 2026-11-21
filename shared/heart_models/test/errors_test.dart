import 'dart:convert';

import 'package:heart_models/heart_models.dart';
import 'package:test/test.dart';

void main() {
  group('ServerRefusal.tryParse', () {
    test('reads the code and keeps the rest of the body as details', () {
      final body = jsonDecode('{"error": "too many requests", "code": "rate_limited", "retryAfter": 30}');
      final refusal = ServerRefusal.tryParse(status: 429, route: '/v1/goals', body: body)!;

      expect(refusal.status, 429);
      expect(refusal.code, 'rate_limited');
      expect(refusal.route, '/v1/goals');
      expect(refusal.details, {'error': 'too many requests', 'retryAfter': 30});
    });

    test('carries a code this build does not know as sent', () {
      final body = jsonDecode('{"code": "some_future_code", "newField": [1, 2]}');
      final refusal = ServerRefusal.tryParse(status: 409, route: '/v1/templates', body: body)!;

      expect(refusal.code, 'some_future_code');
      expect(refusal.details, {
        'newField': [1, 2],
      });
    });

    test('a body without a code is not a refusal', () {
      // API Gateway's own throttle answers 429 with a body of its own shape.
      final body = jsonDecode('{"message": "Too Many Requests"}');
      expect(ServerRefusal.tryParse(status: 429, route: '/v1/goals', body: body), isNull);
    });

    test('a code that is not a string is not a refusal', () {
      expect(ServerRefusal.tryParse(status: 400, route: '/v1/goals', body: {'code': 7}), isNull);
    });

    for (final body in [null, '', 'not found', <dynamic>[]]) {
      test('a body that is not a JSON object ("$body") is not a refusal', () {
        expect(ServerRefusal.tryParse(status: 404, route: '/v1/goals/{id}', body: body), isNull);
      });
    }

    for (final status in [200, 302, 500, 503]) {
      test('a $status is not a refusal, even with a code', () {
        final body = {'error': 'server error', 'code': 'server_error'};
        expect(ServerRefusal.tryParse(status: status, route: '/v1/goals', body: body), isNull);
      });
    }

    test('details cannot be changed', () {
      final refusal = ServerRefusal.tryParse(status: 403, route: '/v1/goals', body: {'code': 'goal_limit'})!;
      expect(() => refusal.details['code'] = 'other', throwsUnsupportedError);
    });
  });

  test('toString names the status, code and route, never the body', () {
    final body = jsonDecode('{"code": "name_taken", "error": "the name \\"my secret plan\\" is taken"}');
    final refusal = ServerRefusal.tryParse(status: 409, route: '/v1/templates/{id}', body: body)!;

    expect(refusal.toString(), 'ServerRefusal: 409 name_taken at /v1/templates/{id}');
    expect(refusal.toString(), isNot(contains('secret')));
  });
}
