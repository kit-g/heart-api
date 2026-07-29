import 'dart:convert';
import 'dart:io';

import 'package:heart/core/app.dart';
import 'package:heart/globals/firebase.dart';
import 'package:heart/middleware/aws.dart';
import 'package:heart_aws/heart_aws.dart';
import 'package:heart_models/heart_models.dart';
import 'package:mockito/mockito.dart';
import 'package:relic/relic.dart';

import '../mocks.mocks.dart';

/// Boots the real [buildApp] wiring on an ephemeral loopback port and drives
/// genuine HTTP requests through it, with the leaf services and token verifier
/// replaced by mocks. This is the shared rig for the route-level integration
/// tests: a handler is exercised across the full production chain (version →
/// config → auth → service bindings → router → `apiHandler` error mapping)
/// rather than called in isolation.
///
/// A single [MockDatabase] backs every db service (the real [Database]
/// implements them all), [MockStorage] backs S3, and [config] is exposed so a
/// test can stub the request-time knobs a given handler reads (allowed mime
/// types, locales, `cdnAssetUrl`, …). The default token is `'good'`; anything
/// else is rejected the way Firebase would reject a bad credential.
class AppHarness {
  final MockDatabase db;
  final MockStorage storage;
  final MockEventPublisher events;
  final MockAppConfig config;
  final RelicApp _app;
  final RelicServer _server;

  AppHarness._(this.db, this.storage, this.events, this.config, this._app, this._server);

  static const goodToken = 'good';

  static Future<AppHarness> start({User? user}) async {
    final db = MockDatabase();
    final storage = MockStorage();
    final events = MockEventPublisher();
    final config = MockAppConfig();
    when(config.minimalAppVersion).thenReturn('1.0.0');
    when(config.shouldCheckVersion).thenReturn(false);
    when(config.firebaseProjectId).thenReturn('proj');

    final authenticated = user ?? User(id: 'u1', displayName: 'Sam');
    Future<User> verify(String _, String token) async {
      if (token == goodToken) return authenticated;
      throw AuthenticationError();
    }

    final app = buildApp(
      config: config,
      aws: AwsConfig(credentialsProvider: const AWSCredentialsProvider.defaultChain(), region: 'us-east-1'),
      database: db,
      storage: storage,
      eventPublisher: events,
      auth: verify,
    );
    final server = await app.serve(port: 0);
    return AppHarness._(db, storage, events, config, app, server);
  }

  Future<void> stop() => _app.close();

  /// Sends [method] [path] and returns the status and raw body. Attaches a
  /// `Bearer` token by default (pass `token: null` to hit a route anonymously)
  /// and JSON-encodes [body] when present.
  Future<({int status, String body})> send(
    String method,
    String path, {
    String? token = goodToken,
    Object? body,
    String? appVersion,
  }) async {
    final client = HttpClient();
    try {
      final request = await client.openUrl(method, Uri.parse('http://127.0.0.1:${_server.port}$path'));
      if (token != null) request.headers.set('authorization', 'Bearer $token');
      if (appVersion != null) request.headers.set('x-app-version', appVersion);
      if (body != null) {
        request.headers.contentType = ContentType.json;
        request.write(jsonEncode(body));
      }
      final response = await request.close();
      final text = await response.transform(utf8.decoder).join();
      return (status: response.statusCode, body: text);
    } finally {
      client.close();
    }
  }
}
