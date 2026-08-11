import 'dart:convert';
import 'dart:io';

import 'package:heart/core/app.dart';
import 'package:heart/globals/firebase.dart';
import 'package:heart/middleware/aws.dart';
import 'package:heart/models/errors.dart';
import 'package:heart_aws/heart_aws.dart';
import 'package:heart_models/heart_models.dart';
import 'package:mockito/mockito.dart';
import 'package:relic/relic.dart';
import 'package:test/test.dart';

import '../mocks.mocks.dart';

/// End-to-end tests that drive real HTTP requests through the fully-wired app
/// [buildApp] returns. Nothing here is stubbed except the leaf services and the
/// token verifier — every request travels the production middleware chain (log
/// → version → config → auth → service bindings), the real router, and the real
/// [apiHandler] error mapping. This is the only layer that proves the pieces are
/// wired together: that routes sit at the paths/verbs they claim, that auth
/// guards them, and that handler results become the right HTTP status + body.
void main() {
  late MockDatabase db;
  late RelicApp app;
  late RelicServer server;
  late int port;

  /// Verifies [token], accepting only `'good'`; anything else is rejected the
  /// way Firebase would reject a bad credential.
  Future<User> verifyToken(String _, String token) async {
    if (token == 'good') return User(id: 'u1', displayName: 'Sam');
    throw AuthenticationError();
  }

  setUp(() async {
    db = MockDatabase();

    final config = MockAppConfig();
    when(config.minimalAppVersion).thenReturn('1.0.0');
    when(config.shouldCheckVersion).thenReturn(false);
    when(config.firebaseProjectId).thenReturn('proj');

    app = buildApp(
      config: config,
      aws: AwsConfig(credentialsProvider: const AWSCredentialsProvider.defaultChain(), region: 'us-east-1'),
      database: db,
      storage: MockStorage(),
      eventPublisher: MockEventPublisher(),
      auth: verifyToken,
    );

    server = await app.serve(port: 0);
    port = server.port;
  });

  tearDown(() => app.close());

  Future<({int status, String body})> send(
    String method,
    String path, {
    String? token,
    String? appVersion,
  }) async {
    final client = HttpClient();
    try {
      final request = await client.openUrl(method, Uri.parse('http://127.0.0.1:$port$path'));
      if (token != null) request.headers.set('authorization', 'Bearer $token');
      if (appVersion != null) request.headers.set('x-app-version', appVersion);
      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();
      return (status: response.statusCode, body: body);
    } finally {
      client.close();
    }
  }

  group('authentication', () {
    test('a public route is reachable without a token', () async {
      final res = await send('GET', '/version');
      expect(res.status, 200);
      expect(jsonDecode(res.body), containsPair('commit', anything));
    });

    test('a protected route returns 401 without a token', () async {
      expect((await send('GET', '/accounts/u1/goals')).status, 401);
    });

    test('a protected route returns 401 for a rejected token', () async {
      expect((await send('GET', '/accounts/u1/goals', token: 'bad')).status, 401);
    });

    test('a valid token reaches the handler and serializes the result', () async {
      when(
        db.getTargetUserGoals(
          requesterId: anyNamed('requesterId'),
          targetUserId: anyNamed('targetUserId'),
          archived: anyNamed('archived'),
        ),
      ).thenAnswer((_) async => const <Goal>[]);

      final res = await send('GET', '/accounts/u1/goals', token: 'good');
      expect(res.status, 200);
      expect(jsonDecode(res.body), containsPair('goals', isEmpty));
      // the authenticated user's id is threaded through as the requester, and the
      // absent query flag defaults to the live slice
      verify(db.getTargetUserGoals(requesterId: 'u1', targetUserId: 'u1', archived: false)).called(1);
    });

    test('the ?archived=true query flag reaches the service', () async {
      when(
        db.getTargetUserGoals(
          requesterId: anyNamed('requesterId'),
          targetUserId: anyNamed('targetUserId'),
          archived: anyNamed('archived'),
        ),
      ).thenAnswer((_) async => const <Goal>[]);

      final res = await send('GET', '/accounts/u1/goals?archived=true', token: 'good');
      expect(res.status, 200);
      verify(db.getTargetUserGoals(requesterId: 'u1', targetUserId: 'u1', archived: true)).called(1);
    });
  });

  group('routing + path parameters', () {
    test('an unknown path falls through to 404 (once authenticated)', () async {
      expect((await send('GET', '/does-not-exist', token: 'good')).status, 404);
    });

    test('a :pathParameter is captured and passed to the service', () async {
      when(db.deleteGoal(any, any)).thenAnswer((_) async {});

      final res = await send('DELETE', '/goals/g-42', token: 'good');
      expect(res.status, 204); // NoContent -> 204, empty body
      expect(res.body, isEmpty);
      verify(db.deleteGoal('g-42', 'u1')).called(1);
    });
  });

  group('error mapping', () {
    test('an ApiException thrown by a service becomes its HTTP status', () async {
      when(db.deleteGoal(any, any)).thenThrow(const NotFound(type: 'goal', id: 'g-42'));

      final res = await send('DELETE', '/goals/g-42', token: 'good');
      expect(res.status, 404);
      expect(jsonDecode(res.body), containsPair('error', 'not found'));
    });
  });

  group('version gate', () {
    test('426 when the client version is below the minimum', () async {
      await app.close(); // replace the setUp app with one whose config enforces versions
      when(
        db.getTargetUserGoals(requesterId: anyNamed('requesterId'), targetUserId: anyNamed('targetUserId')),
      ).thenAnswer((_) async => const <Goal>[]);
      // The gate only fires on non-exempt routes when the config demands it.
      final config = MockAppConfig();
      when(config.minimalAppVersion).thenReturn('2.0.0');
      when(config.shouldCheckVersion).thenReturn(true);
      when(config.firebaseProjectId).thenReturn('proj');
      app = buildApp(
        config: config,
        aws: AwsConfig(credentialsProvider: const AWSCredentialsProvider.defaultChain(), region: 'us-east-1'),
        database: db,
        storage: MockStorage(),
        eventPublisher: MockEventPublisher(),
        auth: verifyToken,
      );
      server = await app.serve(port: 0);
      port = server.port;

      expect((await send('GET', '/accounts/u1/goals', token: 'good', appVersion: '1.0.0')).status, 426);
      expect((await send('GET', '/accounts/u1/goals', token: 'good', appVersion: '2.1.0')).status, 200);
    });
  });
}
