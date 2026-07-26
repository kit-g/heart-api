import 'package:heart/core/response.dart';
import 'package:heart/globals/config.dart';
import 'package:heart/globals/firebase.dart';
import 'package:heart/globals/globals.dart';
import 'package:heart/middleware/authentication.dart';
import 'package:heart/middleware/version.dart';
import 'package:heart/routes/index.dart';
import 'package:heart_models/heart_models.dart';
import 'package:mockito/mockito.dart';
import 'package:relic/relic.dart';
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
