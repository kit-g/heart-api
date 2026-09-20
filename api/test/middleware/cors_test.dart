import 'package:heart/core/response.dart';
import 'package:heart/middleware/cors.dart';
import 'package:mockito/mockito.dart';
import 'package:relic/relic.dart';
import 'package:test/test.dart';

import '../helpers/app_harness.dart';
import '../helpers/request.dart';

const _allowed = 'https://heart-of.me';
const _stranger = 'https://not-heart-of.me';

/// A terminal handler that signals "the chain let me through" with a 200.
Response _next(Request _) => JsonResponse.ok();

Future<Response> _run(
  Request request, {
  Set<String> origins = const {_allowed},
  Set<Method> methods = const {Method.get, Method.post},
  Handler? next,
}) async {
  final handler = cors(origins: origins, methods: methods)(next ?? _next);
  return await handler(request) as Response;
}

Request _req({String? origin, Method method = Method.get}) {
  return bareRequest(
    method: method,
    extraHeaders: {'origin': ?origin},
  );
}

void main() {
  group('cors, on its own', () {
    test('a request with no Origin comes back untouched', () async {
      final response = await _run(_req());

      expect(response.statusCode, 200);
      expect(response.headers.accessControlAllowOrigin, isNull);
      expect(response.headers.vary, isNull);
    });

    test('an allowed Origin is echoed back, and the response says it varies by one', () async {
      final response = await _run(_req(origin: _allowed));

      expect(response.headers.accessControlAllowOrigin?.origin.toString(), _allowed);
      expect(response.headers.vary?.fields, contains('origin'));
    });

    test('an unknown Origin still gets Vary, but is never allowed', () async {
      final response = await _run(_req(origin: _stranger));

      expect(response.statusCode, 200, reason: 'the handler still runs; only the browser refuses the result');
      expect(response.headers.accessControlAllowOrigin, isNull);
      expect(response.headers.vary?.fields, contains('origin'));
    });

    test('the allowlist is exact — a prefix of an allowed origin is a stranger', () async {
      final response = await _run(_req(origin: 'https://heart-of.me.evil.test'));

      expect(response.headers.accessControlAllowOrigin, isNull);
    });
  });

  group('cors preflight', () {
    test('answers OPTIONS itself, without ever calling the handler', () async {
      var reached = false;
      final response = await _run(
        _req(origin: _allowed, method: Method.options),
        next: (_) {
          reached = true;
          return JsonResponse.ok();
        },
      );

      expect(reached, isFalse, reason: 'the route table carries no OPTIONS; letting one through is a 404');
      expect(response.statusCode, 204);
    });

    test('states the methods it was given, not a wildcard', () async {
      final response = await _run(
        _req(origin: _allowed, method: Method.options),
        methods: const {Method.get, Method.delete},
      );

      expect(response.headers.accessControlAllowMethods?.methods, containsAll([Method.get, Method.delete]));
      expect(response.headers.accessControlAllowMethods?.isWildcard, isFalse);
    });

    test('allows the headers every call actually carries', () async {
      final response = await _run(_req(origin: _allowed, method: Method.options));

      // Without these two a browser refuses the request before it is sent:
      // neither is CORS-safelisted, and every authenticated call has both.
      expect(response.headers.accessControlAllowHeaders?.headers, containsAll(['authorization', 'content-type']));
      expect(response.headers.accessControlAllowHeaders?.headers, containsAll(['x-app-version', 'accept-language']));
    });

    test('is cacheable, so the extra round trip is paid once', () async {
      final response = await _run(_req(origin: _allowed, method: Method.options));

      expect(response.headers.accessControlMaxAge, greaterThan(0));
    });

    test('never carries Allow-Credentials — the session is a bearer token, not a cookie', () async {
      final response = await _run(_req(origin: _allowed, method: Method.options));

      expect(response.headers.accessControlAllowCredentials, isNull);
    });

    test('a preflight from a stranger is answered, but allows nothing', () async {
      final response = await _run(_req(origin: _stranger, method: Method.options));

      expect(response.statusCode, 204);
      expect(response.headers.accessControlAllowOrigin, isNull);
      expect(response.headers.accessControlAllowMethods, isNull);
    });

    test('a bare OPTIONS with no Origin is not a preflight, and falls through', () async {
      var reached = false;
      await _run(
        _req(method: Method.options),
        next: (_) {
          reached = true;
          return JsonResponse.ok();
        },
      );

      expect(reached, isTrue);
    });
  });

  /// The ordering is the whole point, and it only exists in `buildApp` — so it
  /// is pinned through the real chain rather than against a stub handler.
  group('cors in the real chain', () {
    late AppHarness app;

    setUp(() async => app = await AppHarness.start(allowedOrigins: const {_allowed}));
    tearDown(() => app.stop());

    test('a preflight on a real route is answered, though it carries neither token nor app version', () async {
      final response = await app.send(
        'OPTIONS',
        '/templates',
        token: null,
        extraHeaders: const {'origin': _allowed, 'access-control-request-method': 'GET'},
      );

      expect(response.status, 204, reason: 'authentication would 401 this, and the version gate 426 it');
      expect(response.headers['access-control-allow-origin'], _allowed);
      expect(response.headers['access-control-allow-methods'], isNotNull);
    });

    test('the version gate does not reach a preflight even when it is switched on', () async {
      when(app.config.shouldCheckVersion).thenReturn(true);

      final response = await app.send(
        'OPTIONS',
        '/templates',
        token: null,
        extraHeaders: const {'origin': _allowed, 'access-control-request-method': 'GET'},
      );

      expect(response.status, 204, reason: 'a preflight carries no x-app-version, so the gate would 426 it');
    });

    test('a 404 for an unknown path still carries the headers', () async {
      final response = await app.send('GET', '/no-such-thing', extraHeaders: const {'origin': _allowed});

      expect(response.status, 404);
      expect(
        response.headers['access-control-allow-origin'],
        _allowed,
        reason: 'the fallback is not a stored route, so it is wrapped separately',
      );
    });

    test('a refusal reaches the browser as a refusal, not as a network error', () async {
      final response = await app.send('GET', '/templates', token: null, extraHeaders: const {'origin': _allowed});

      expect(response.status, 401);
      expect(
        response.headers['access-control-allow-origin'],
        _allowed,
        reason: 'without this the browser reports an opaque CORS failure and hides the 401',
      );
    });

    test('the mobile app, which sends no Origin, gets no CORS headers at all', () async {
      final response = await app.send('GET', '/version', token: null);

      expect(response.headers.containsKey('access-control-allow-origin'), isFalse);
      expect(response.headers.containsKey('vary'), isFalse);
    });
  });
}
