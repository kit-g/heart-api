import 'dart:async';

import 'package:heart/core/response.dart';
import 'package:heart/globals/config.dart';
import 'package:heart/globals/firebase.dart';
import 'package:heart/globals/globals.dart';
import 'package:heart/middleware/authentication.dart';
import 'package:heart/middleware/logging.dart';
import 'package:heart/middleware/version.dart';
import 'package:heart/routes/index.dart';
import 'package:heart_models/heart_models.dart';
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:relic/relic.dart' hide Logger;
import 'package:test/test.dart';

import '../helpers/request.dart';
import '../mocks.mocks.dart';

/// A terminal handler that signals "the chain let me through" with a 200.
Response _next(Request _) => JsonResponse.ok();

Future<int> _status(Handler handler, Request request) async {
  final result = await handler(request);
  return (result as Response).statusCode;
}

void main() {
  group('authentication', () {
    late MockAppConfig config;

    setUp(() {
      config = MockAppConfig();
      when(config.firebaseProjectId).thenReturn('proj');
    });

    Request req({String? bearer}) {
      final r = bareRequest(extraHeaders: {if (bearer != null) 'authorization': 'Bearer $bearer'})..config = config;
      return r;
    }

    test('passes through without auth when the route is exempt', () async {
      final handler = authentication(shouldAuthenticate: (_) => false)(_next);
      expect(await _status(handler, bareRequest()), 200);
    });

    test('401 when authentication is required and no bearer token is present', () async {
      final handler = authentication(shouldAuthenticate: (_) => true)(_next);
      expect(await _status(handler, req()), 401);
    });

    test('accepts a valid token, sets the user, and continues', () async {
      final handler = authentication(shouldAuthenticate: (_) => true)(_next);
      final request = req(bearer: 'good')..authenticator = (_, _) async => User(id: 'u1', displayName: 'Sam');

      expect(await _status(handler, request), 200);
      expect(request.user.id, 'u1');
    });

    test('401 when the authenticator rejects the token', () async {
      final handler = authentication(shouldAuthenticate: (_) => true)(_next);
      final request = req(bearer: 'bad')..authenticator = (_, _) async => throw AuthenticationError();

      expect(await _status(handler, request), 401);
    });

    test('401 (not 500) when the authenticator throws something unexpected', () async {
      final handler = authentication(shouldAuthenticate: (_) => true)(_next);
      final request = req(bearer: 'x')..authenticator = (_, _) async => throw StateError('boom');

      expect(await _status(handler, request), 401);
    });

    test('403 with code anonymous_account when the authenticator rejects an anonymous token', () async {
      var nextCalled = false;
      Response next(Request _) {
        nextCalled = true;
        return JsonResponse.ok();
      }

      final handler = authentication(shouldAuthenticate: (_) => true)(next);
      final request = req(bearer: 'anon')..authenticator = (_, _) async => throw AnonymousAccountError();

      final result = await handler(request) as Response;
      expect(result.statusCode, 403);
      expect(await result.readAsString(), contains('anonymous_account'));
      expect(nextCalled, isFalse);
    });
  });

  group('version', () {
    Handler gate({bool check = true}) => version(minimal: '1.2.0', shouldCheckVersion: (_) => check)(_next);

    Request withVersion(String? v) => bareRequest(extraHeaders: {'x-app-version': ?v});

    test('allows a version at or above the minimum', () async {
      expect(await _status(gate(), withVersion('1.2.0')), 200);
      expect(await _status(gate(), withVersion('1.3.0')), 200);
    });

    test('426 for a version below the minimum', () async {
      expect(await _status(gate(), withVersion('1.0.0')), 426);
    });

    test('426 when the version header is missing', () async {
      expect(await _status(gate(), withVersion(null)), 426);
    });

    test('skips the check when not required', () async {
      expect(await _status(gate(check: false), withVersion('0.0.1')), 200);
    });
  });

  group('requestLogging', () {
    late List<LogRecord> records;
    late StreamSubscription<LogRecord> subscription;

    setUp(() {
      records = [];
      Logger.root.level = Level.ALL;
      subscription = Logger.root.onRecord.listen(records.add);
    });

    tearDown(() async => subscription.cancel());

    test('logs exactly one record per request', () async {
      await requestLogging()(_next)(bareRequest(path: '/workouts'));
      expect(records, hasLength(1));
    });

    test('logs elapsed time, method, status and path — and no timestamp of its own', () async {
      await requestLogging()(_next)(bareRequest(method: Method.post, path: '/workouts'));

      // initLogging stamps every record with `time`; a second one in the
      // message would be duplicated bytes in CloudWatch.
      expect(records.single.message, matches(RegExp(r'^\d+\.\d+ms POST \[200\] /workouts$')));
    });

    test('includes the query string', () async {
      await requestLogging()(_next)(bareRequest(path: '/workouts', query: {'limit': '10'}));
      expect(records.single.message, endsWith('/workouts?limit=10'));
    });

    test('logs the failure and rethrows when the handler throws', () async {
      Never boom(Request _) => throw StateError('boom');
      final handler = requestLogging()(boom);

      await expectLater(handler(bareRequest(path: '/workouts')), throwsStateError);
      expect(records.single.level, Level.SEVERE);
      expect(records.single.message, contains('[ERROR] /workouts'));
      expect(records.single.error, isStateError);
    });
  });

  group('isPublicRoute (auth-bypass gate)', () {
    // Named from the auth angle: returns false for exempt routes (don't
    // authenticate), true for everything else.
    test('public routes are exempt from auth', () {
      expect(isPublicRoute(bareRequest(path: '/version')), isFalse);
      expect(isPublicRoute(bareRequest(path: '/events')), isFalse);
    });

    test('everything else requires auth', () {
      expect(isPublicRoute(bareRequest(path: '/workouts')), isTrue);
      expect(isPublicRoute(bareRequest(path: '/goals')), isTrue);
    });
  });
}
