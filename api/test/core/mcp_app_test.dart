import 'dart:convert';

import 'package:heart/globals/config.dart';
import 'package:heart/models/tokens.dart';
import 'package:heart_models/heart_models.dart';
import 'package:mockito/mockito.dart';
import 'package:test/test.dart';

import '../helpers/app_harness.dart';

/// The MCP host's app (`HEART_SURFACE=mcp`): the MCP server at the root of its
/// own host, and none of the app's API.
void main() {
  late AppHarness app;
  final secret = TokenSecret.mint();
  final now = DateTime.now().toUtc();

  setUp(() async {
    app = await AppHarness.start(surface: 'mcp');
    when(app.config.freeApiLimits).thenReturn(ApiLimits.free);
    when(app.db.useToken(TokenSecret.hash(secret), count: anyNamed('count'))).thenAnswer(
      (_) async => (
        userId: 'u1',
        resource: null,
        clientId: null,
        scopes: const ['read'],
        purpose: ApiTokenPurpose.aiAssistant,
        minuteStart: now,
        minuteCount: 1,
        dayStart: now,
        dayCount: 1,
      ),
    );
  });

  tearDown(() => app.stop());

  test('the MCP server answers at the root', () async {
    final response = await app.send(
      'POST',
      '/',
      token: secret,
      body: {'jsonrpc': '2.0', 'id': 1, 'method': 'tools/list'},
    );
    expect(response.status, 200);
    final tools = ((jsonDecode(response.body) as Map)['result'] as Map)['tools'] as List;
    expect(tools.map((t) => (t as Map)['name']), contains('list_workouts'));
  });

  test('GET and DELETE are 405, as on the API', () async {
    expect((await app.send('GET', '/', token: secret)).status, 405);
    expect((await app.send('DELETE', '/', token: secret)).status, 405);
  });

  test("none of the app's API is here", () async {
    final response = await app.send('GET', '/workouts');
    expect(response.status, 404);
    expect((jsonDecode(response.body) as Map)['code'], 'route_not_found');
  });

  test('its resource metadata sits at the root of the host', () async {
    when(app.config.oauth).thenReturn(
      OAuthConfig(
        issuer: Uri.parse('https://heart.example'),
        apiBase: Uri.parse('https://api.heart.example/v1'),
        mcpResource: 'https://mcp.heart.example',
      ),
    );
    final response = await app.send('GET', '/.well-known/oauth-protected-resource', token: null);
    expect(response.status, 200);
    expect((jsonDecode(response.body) as Map)['resource'], 'https://mcp.heart.example');
  });

  group('behind CloudFront', () {
    late AppHarness locked;
    setUp(() async => locked = await AppHarness.start(surface: 'mcp', originSecret: 's3cret'));
    tearDown(() => locked.stop());

    test('a request without the origin secret is refused', () async {
      final bypass = await locked.send(
        'POST',
        '/',
        token: secret,
        body: {'jsonrpc': '2.0', 'id': 1, 'method': 'tools/list'},
      );
      expect(bypass.status, 403);
      expect((jsonDecode(bypass.body) as Map)['code'], 'origin');

      final wrong = await locked.send('GET', '/', extraHeaders: {'x-heart-origin': 's3creT'});
      expect(wrong.status, 403);
    });

    test('with it, the request goes through', () async {
      final through = await locked.send('GET', '/', extraHeaders: {'x-heart-origin': 's3cret'});
      expect(through.status, 405, reason: 'past the lock, the MCP server answers');
    });
  });
}
