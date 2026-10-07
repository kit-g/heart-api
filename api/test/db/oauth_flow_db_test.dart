@Tags(['db'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:heart/core/app.dart';
import 'package:heart/globals/config.dart';
import 'package:heart/middleware/aws.dart';
import 'package:heart/models/tokens.dart';
import 'package:heart_aws/heart_aws.dart';
import 'package:heart_models/heart_models.dart';
import 'package:mockito/mockito.dart';
import 'package:relic/relic.dart';
import 'package:test/test.dart';

import '../mocks.mocks.dart';
import 'db_test_utility.dart';

/// The authorization server end to end, over HTTP, against a live Postgres:
/// a host discovers it from the MCP server's 401, sends the account through
/// consent, exchanges the code, calls MCP with the token, refreshes, and
/// loses everything when a refresh token is replayed. Only the fetch of the
/// client's metadata document is faked.
///
/// Tagged `db` — skipped by the default `dart test`. Run with:
///   dart test --run-skipped -t db
void main() {
  final h = _Harness();
  late RelicApp app;
  late RelicServer server;
  late String user;

  final oauth = OAuthConfig(
    issuer: Uri.parse('https://site.example'),
    apiBase: Uri.parse('https://api.example/v1'),
    mcpResource: 'https://api.example/v1/mcp',
  );
  late String clientId;
  const redirect = 'https://client.example/callback';
  const firebaseToken = 'firebase-session';

  final verifier = base64Url.encode(List.generate(40, (i) => i)).replaceAll('=', '');
  final challenge = base64Url.encode(sha256.convert(ascii.encode(verifier)).bytes).replaceAll('=', '');

  setUpAll(() async {
    await h.setupDatabase();
    user = await h.seedProfile();
    clientId = 'https://client.example/${h.uid('meta')}';

    final config = MockAppConfig();
    when(config.minimalAppVersion).thenReturn('1.0.0');
    when(config.shouldCheckVersion).thenReturn(true);
    when(config.firebaseProjectId).thenReturn('proj');
    when(config.allowedOrigins).thenReturn({'https://site.example'});
    when(config.oauth).thenReturn(oauth);
    when(config.freeApiLimits).thenReturn(ApiLimits.free);

    Future<Map<String, dynamic>> fetch(Uri uri) async {
      if (uri.toString() != clientId) throw StateError('unexpected fetch of $uri');
      return {
        'client_id': clientId,
        'client_name': 'Test Assistant',
        'redirect_uris': [redirect],
        'token_endpoint_auth_method': 'none',
      };
    }

    app = buildApp(
      config: config,
      aws: AwsConfig(credentialsProvider: const AWSCredentialsProvider.defaultChain(), region: 'us-east-1'),
      database: h.db,
      storage: MockStorage(),
      eventPublisher: MockEventPublisher(),
      apple: MockAppleIdentityService(),
      auth: (_, token) async => token == firebaseToken ? User(id: user) : throw StateError('bad token'),
      fetch: fetch,
    );
    server = await app.serve(port: 0);
  });

  tearDownAll(() async {
    await app.close();
    await h.exec('DELETE FROM oauth_clients WHERE client_id = @id', {'id': clientId});
    await h.teardownDatabase();
  });

  Future<({int status, String body, HttpHeaders headers})> send(
    String method,
    String path, {
    String? bearer,
    Object? json,
    Map<String, String>? form,
    String? appVersion,
    Map<String, String> headers = const {},
  }) async {
    final client = HttpClient();
    try {
      final request = await client.openUrl(method, Uri.parse('http://127.0.0.1:${server.port}$path'))
        ..followRedirects = false;
      if (bearer != null) request.headers.set('authorization', 'Bearer $bearer');
      if (appVersion != null) request.headers.set('x-app-version', appVersion);
      headers.forEach(request.headers.set);
      if (json != null) {
        request.headers.contentType = ContentType.json;
        request.write(jsonEncode(json));
      }
      if (form != null) {
        request.headers.contentType = ContentType('application', 'x-www-form-urlencoded');
        request.write(Uri(queryParameters: form).query);
      }
      final response = await request.close();
      return (
        status: response.statusCode,
        body: await response.transform(utf8.decoder).join(),
        headers: response.headers,
      );
    } finally {
      client.close();
    }
  }

  Map<String, dynamic> body(({int status, String body, HttpHeaders headers}) r) =>
      jsonDecode(r.body) as Map<String, dynamic>;

  Map<String, dynamic> mcp(String method) => {'jsonrpc': '2.0', 'id': 1, 'method': method};

  test('discovery: an MCP call without a token points at the resource metadata, which names the issuer', () async {
    final denied = await send('POST', '/mcp', json: mcp('tools/list'));
    expect(denied.status, 401);
    final challenge = denied.headers.value('www-authenticate')!;
    expect(challenge, contains('resource_metadata="https://api.example/v1/mcp/.well-known/oauth-protected-resource"'));
    expect(challenge, contains('scope="read"'));

    final metadata = await send('GET', '/mcp/.well-known/oauth-protected-resource');
    expect(body(metadata), containsPair('resource', 'https://api.example/v1/mcp'));
    expect(body(metadata)['authorization_servers'], ['https://site.example']);
  });

  test('the whole flow: consent, code, tokens, MCP, refresh, replay, disconnect', () async {
    // /authorize hands the browser to the consent page
    final authorize = await send(
      'GET',
      '/oauth/authorize?${Uri(queryParameters: {
        'response_type': 'code',
        'client_id': clientId,
        'redirect_uri': redirect,
        'code_challenge': challenge,
        'code_challenge_method': 'S256',
        'resource': oauth.mcpResource,
        'state': 'xyz',
      }).query}',
    );
    expect(authorize.status, 302);
    final consent = Uri.parse(authorize.headers.value('location')!);
    expect(consent.origin, 'https://site.example');
    expect(consent.path, '/connect.html');
    final requestId = consent.queryParameters['request']!;

    // the consent page reads the request as the signed-in account, no app version needed
    expect((await send('GET', '/oauth/requests/$requestId')).status, 401);
    final shown = body(await send('GET', '/oauth/requests/$requestId', bearer: firebaseToken));
    expect(shown['client'], {'id': clientId, 'name': 'Test Assistant'});
    expect(shown['redirectHost'], 'client.example');
    expect(shown['resource'], 'mcp');

    // approving sends the browser back with a code, the state and the issuer
    final approved = body(await send('POST', '/oauth/requests/$requestId/approve', bearer: firebaseToken));
    final back = Uri.parse(approved['redirect'] as String);
    expect(back.toString(), startsWith(redirect));
    expect(back.queryParameters['state'], 'xyz');
    expect(back.queryParameters['iss'], 'https://site.example');
    final code = back.queryParameters['code']!;

    // a wrong verifier burns the code
    final wrong = await send(
      'POST',
      '/oauth/token',
      form: {
        'grant_type': 'authorization_code',
        'code': code,
        'code_verifier': 'x' * 43,
        'redirect_uri': redirect,
        'client_id': clientId,
      },
    );
    expect(wrong.status, 400);
    expect(body(wrong)['error'], 'invalid_grant');

    // so the flow starts again, and this time the exchange is right
    final again = await send(
      'GET',
      '/oauth/authorize?${Uri(queryParameters: {
        'response_type': 'code',
        'client_id': clientId,
        'redirect_uri': redirect,
        'code_challenge': challenge,
        'code_challenge_method': 'S256',
        'resource': oauth.mcpResource,
      }).query}',
    );
    final secondId = Uri.parse(again.headers.value('location')!).queryParameters['request']!;
    final secondCode = Uri.parse(
      body(await send('POST', '/oauth/requests/$secondId/approve', bearer: firebaseToken))['redirect'] as String,
    ).queryParameters['code']!;
    final exchanged = await send(
      'POST',
      '/oauth/token',
      form: {
        'grant_type': 'authorization_code',
        'code': secondCode,
        'code_verifier': verifier,
        'redirect_uri': redirect,
        'client_id': clientId,
        'resource': oauth.mcpResource,
      },
    );
    expect(exchanged.status, 200, reason: exchanged.body);
    expect(exchanged.headers.value('cache-control'), contains('no-store'));
    final tokens = body(exchanged);
    expect(tokens['token_type'], 'Bearer');
    expect(tokens['expires_in'], 3600);
    expect(tokens['scope'], 'read');
    final access = tokens['access_token'] as String;
    final refresh = tokens['refresh_token'] as String;
    expect(access, startsWith(TokenSecret.accessPrefix));

    // the token works on the MCP server it was issued for, and only there
    expect((await send('POST', '/mcp', bearer: access, json: mcp('tools/list'))).status, 200);
    expect((await send('GET', '/me', bearer: access)).status, 401, reason: 'bound to the MCP resource');

    // the account sees the connection
    final apps =
        body(await send('GET', '/accounts/connected-apps', bearer: firebaseToken, appVersion: '9.9.9'))['apps'] as List;
    expect(apps.single, containsPair('name', 'Test Assistant'));

    // refresh rotates; replaying the old refresh token revokes everything
    final refreshed = body(
      await send(
        'POST',
        '/oauth/token',
        form: {'grant_type': 'refresh_token', 'refresh_token': refresh, 'client_id': clientId},
      ),
    );
    final newAccess = refreshed['access_token'] as String;
    expect((await send('POST', '/mcp', bearer: newAccess, json: mcp('tools/list'))).status, 200);

    // a replay inside a minute is a retry: refused, nothing revoked
    final retry = await send(
      'POST',
      '/oauth/token',
      form: {'grant_type': 'refresh_token', 'refresh_token': refresh, 'client_id': clientId},
    );
    expect(body(retry)['error'], 'invalid_grant');
    expect((await send('POST', '/mcp', bearer: newAccess, json: mcp('tools/list'))).status, 200);

    // after it, a replay means a copy exists: everything goes
    await h.exec(
      "UPDATE oauth_refresh_tokens SET rotated_at = now() - interval '2 minutes' WHERE rotated_at IS NOT NULL "
      'AND grant_id IN (SELECT id FROM oauth_grants WHERE user_id = @u)',
      {'u': user},
    );
    final replay = await send(
      'POST',
      '/oauth/token',
      form: {'grant_type': 'refresh_token', 'refresh_token': refresh, 'client_id': clientId},
    );
    expect(body(replay)['error'], 'invalid_grant');
    expect((await send('POST', '/mcp', bearer: newAccess, json: mcp('tools/list'))).status, 401);
    expect(
      body(await send('GET', '/accounts/connected-apps', bearer: firebaseToken, appVersion: '9.9.9'))['apps'],
      isEmpty,
    );
  });

  test('an unregistered redirect is refused here, never followed', () async {
    final response = await send(
      'GET',
      '/oauth/authorize?${Uri(queryParameters: {
        'response_type': 'code',
        'client_id': clientId,
        'redirect_uri': 'https://evil.example/cb',
        'code_challenge': challenge,
        'code_challenge_method': 'S256',
        'resource': oauth.mcpResource,
      }).query}',
    );
    expect(response.status, 400);
    expect(response.headers.value('location'), isNull);
  });

  test('a bad request with a good redirect goes back to the client with the error', () async {
    final response = await send(
      'GET',
      '/oauth/authorize?${Uri(queryParameters: {
        'response_type': 'code',
        'client_id': clientId,
        'redirect_uri': redirect,
        'code_challenge': challenge,
        'code_challenge_method': 'S256',
        'resource': 'https://elsewhere.example',
        'state': 's1',
      }).query}',
    );
    expect(response.status, 302);
    final back = Uri.parse(response.headers.value('location')!);
    expect(back.queryParameters['error'], 'invalid_target');
    expect(back.queryParameters['state'], 's1');
  });

  test('a request without a resource means the MCP server, and foreign scopes are dropped', () async {
    final authorize = await send(
      'GET',
      '/oauth/authorize?${Uri(queryParameters: {
        'response_type': 'code',
        'client_id': clientId,
        'redirect_uri': redirect,
        'code_challenge': challenge,
        'code_challenge_method': 'S256',
        'scope': 'read offline_access',
      }).query}',
    );
    expect(authorize.status, 302);
    final id = Uri.parse(authorize.headers.value('location')!).queryParameters['request']!;
    final shown = body(await send('GET', '/oauth/requests/$id', bearer: firebaseToken));
    expect(shown['resource'], 'mcp');
    expect(shown['scopes'], ['read']);
  });

  test('denying returns access_denied to the client', () async {
    final authorize = await send(
      'GET',
      '/oauth/authorize?${Uri(queryParameters: {
        'response_type': 'code',
        'client_id': clientId,
        'redirect_uri': redirect,
        'code_challenge': challenge,
        'code_challenge_method': 'S256',
        'resource': oauth.meResource,
      }).query}',
    );
    final id = Uri.parse(authorize.headers.value('location')!).queryParameters['request']!;
    final denied = body(await send('POST', '/oauth/requests/$id/deny', bearer: firebaseToken));
    expect(Uri.parse(denied['redirect'] as String).queryParameters['error'], 'access_denied');
  });

  test('dynamic registration issues a client id', () async {
    final registered = await send(
      'POST',
      '/oauth/register',
      json: {
        'client_name': 'Registered',
        'redirect_uris': ['http://127.0.0.1/callback'],
        'token_endpoint_auth_method': 'none',
      },
    );
    expect(registered.status, 201);
    final id = body(registered)['client_id'] as String;
    expect(id, startsWith('dcr_'));
    await h.exec('DELETE FROM oauth_clients WHERE client_id = @id', {'id': id});

    final bad = await send(
      'POST',
      '/oauth/register',
      json: {
        'redirect_uris': ['http://evil.example/cb'],
      },
    );
    expect(body(bad)['error'], 'invalid_client_metadata');
  });

  test('one address registers at most 20 clients a day', () async {
    // as API Gateway reports the caller; a client can't set this one
    final address = '203.0.113.${DateTime.now().microsecond % 250}-${h.token}';
    final context = {
      'x-amzn-request-context': jsonEncode({
        'identity': {'sourceIp': address},
      }),
    };
    for (var i = 0; i < 20; i++) {
      await h.db.countRegistration(address);
    }

    final refused = await send(
      'POST',
      '/oauth/register',
      json: {
        'redirect_uris': ['http://127.0.0.1/callback'],
      },
      headers: context,
    );
    expect(refused.status, 429);
    expect(body(refused)['error'], 'too_many_registrations');
    expect(int.parse(refused.headers.value('retry-after')!), inInclusiveRange(1, 86400));

    final elsewhere = await send(
      'POST',
      '/oauth/register',
      json: {
        'redirect_uris': ['http://127.0.0.1/callback'],
      },
      headers: {
        'x-amzn-request-context': jsonEncode({
          'identity': {'sourceIp': 'other-$address'},
        }),
      },
    );
    expect(elsewhere.status, 201, reason: 'another address is counted on its own');
    await h.exec('DELETE FROM oauth_clients WHERE client_id = @id', {'id': body(elsewhere)['client_id']});
  });
}

class _Harness extends DatabaseTestBase;
