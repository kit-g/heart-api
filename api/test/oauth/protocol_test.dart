import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:heart/models/oauth.dart';
import 'package:heart/oauth/clients.dart';
import 'package:heart/oauth/fetch.dart';
import 'package:heart/oauth/protocol.dart';
import 'package:jose/jose.dart';
import 'package:test/test.dart';

void main() {
  group('verifyPkce', () {
    final verifier = 'a' * 43;
    final challenge = base64Url.encode(sha256.convert(ascii.encode(verifier)).bytes).replaceAll('=', '');

    test('accepts the verifier that hashes to the challenge', () => expect(verifyPkce(verifier, challenge), isTrue));
    test('rejects any other', () => expect(verifyPkce('b' * 43, challenge), isFalse));
    test('rejects a verifier outside 43–128 unreserved characters', () {
      expect(verifyPkce('a' * 42, challenge), isFalse);
      expect(verifyPkce('${'a' * 42}!', challenge), isFalse);
    });
  });

  group('redirectMatches', () {
    test('exact match', () {
      expect(
        redirectMatches('https://claude.ai/api/mcp/auth_callback', ['https://claude.ai/api/mcp/auth_callback']),
        isTrue,
      );
      expect(
        redirectMatches('https://claude.ai/api/mcp/auth_callback/x', ['https://claude.ai/api/mcp/auth_callback']),
        isFalse,
      );
    });

    test('loopback matches on any port, nothing else does', () {
      const registered = ['http://localhost/callback', 'http://127.0.0.1/callback'];
      expect(redirectMatches('http://localhost:53712/callback', registered), isTrue);
      expect(redirectMatches('http://127.0.0.1:8080/callback', registered), isTrue);
      expect(redirectMatches('http://localhost:53712/other', registered), isFalse);
      expect(redirectMatches('https://localhost:53712/callback', registered), isFalse);
      expect(redirectMatches('https://evil.example:443/callback', ['https://evil.example/callback']), isFalse);
    });
  });

  group('parseScopes', () {
    test('absent asks for everything supported', () => expect(parseScopes(null), ['read']));
    test("scopes this server doesn't grant are dropped, as hosts add their own", () {
      expect(parseScopes('read offline_access'), ['read']);
    });
    test('asking only for unknown scopes is an error', () {
      expect(() => parseScopes('openid offline_access'), throwsA(isA<OAuthError>()));
    });
  });

  group('parseClientDocument', () {
    final url = Uri.parse('https://client.example/meta.json');
    final expiry = DateTime.utc(2026, 10, 6);

    test('reads a valid document', () {
      final client = parseClientDocument(url, {
        'client_id': url.toString(),
        'client_name': 'Claude',
        'redirect_uris': ['https://claude.ai/api/mcp/auth_callback', 'http://localhost/callback'],
      }, expiresAt: expiry);
      expect(client.name, 'Claude');
      expect(client.auth, ClientAuth.none);
    });

    test('its client_id must be the URL it came from', () {
      expect(
        () => parseClientDocument(url, {
          'client_id': 'https://other.example/meta.json',
          'redirect_uris': ['https://x.example/cb'],
        }, expiresAt: expiry),
        throwsA(isA<OAuthError>()),
      );
    });

    test('plain http redirects outside loopback are refused', () {
      expect(
        () => parseClientDocument(url, {
          'client_id': url.toString(),
          'redirect_uris': ['http://evil.example/cb'],
        }, expiresAt: expiry),
        throwsA(isA<OAuthError>()),
      );
    });

    test('private_key_jwt needs an https jwks_uri', () {
      expect(
        () => parseClientDocument(url, {
          'client_id': url.toString(),
          'redirect_uris': ['https://x.example/cb'],
          'token_endpoint_auth_method': 'private_key_jwt',
        }, expiresAt: expiry),
        throwsA(isA<OAuthError>()),
      );
    });
  });

  group('normalizeResource', () {
    test('drops a trailing slash only', () {
      expect(normalizeResource('https://api.example/v1/mcp/'), 'https://api.example/v1/mcp');
      expect(normalizeResource('https://api.example/v1/mcp'), 'https://api.example/v1/mcp');
    });
  });

  group('parseRegistration', () {
    test('a client-secret method is replaced with none', () {
      final shape = parseRegistration({
        'redirect_uris': ['https://chatgpt.example/cb'],
        'token_endpoint_auth_method': 'client_secret_post',
      });
      expect(shape.auth, ClientAuth.none);
    });
  });

  group('knownClientMetadata', () {
    test('keeps RFC 7591 fields and nothing else', () {
      expect(knownClientMetadata({'client_name': 'x', 'heart_rate': 60, 'anything': 'else'}), {'client_name': 'x'});
    });
  });

  group('isNonPublicAddress', () {
    for (final address in [
      '127.0.0.1',
      '10.1.2.3',
      '172.16.0.1',
      '172.31.255.255',
      '192.168.1.1',
      '169.254.169.254',
      '100.64.0.1',
      '0.0.0.0',
      '::1',
      'fd00::1',
      'fe80::1',
      '::ffff:10.0.0.1',
    ]) {
      test('$address is not public', () => expect(isNonPublicAddress(InternetAddress(address)), isTrue));
    }
    for (final address in ['8.8.8.8', '172.32.0.1', '2606:4700:4700::1111', '::ffff:1.1.1.1']) {
      test('$address is public', () => expect(isNonPublicAddress(InternetAddress(address)), isFalse));
    }
  });

  group('guardedJsonFetch', () {
    test('refuses anything but plain https', () async {
      for (final url in ['http://client.example/x', 'https://client.example:8443/x', 'https://user@client.example/x']) {
        await expectLater(guardedJsonFetch(Uri.parse(url)), throwsA(isA<DocumentFetchError>()), reason: url);
      }
    });

    test('refuses a host that resolves to a private address', () async {
      await expectLater(guardedJsonFetch(Uri.parse('https://localhost/x')), throwsA(isA<DocumentFetchError>()));
    });
  });

  group('verifyClientAssertion', () {
    final endpoint = Uri.parse('https://api.example/v1/oauth/token');
    final jwks = Uri.parse('https://client.example/jwks.json');
    const clientId = 'https://client.example/meta.json';
    final key = JsonWebKey.generate('RS256');
    final publicJwks = {
      'keys': [
        {...key.toJson()}..removeWhere((k, _) => const {'d', 'p', 'q', 'dp', 'dq', 'qi'}.contains(k)),
      ],
    };
    final client = OAuthClient(
      clientId: clientId,
      kind: .cimd,
      redirectUris: const ['https://client.example/cb'],
      auth: .privateKeyJwt,
      jwksUri: jwks,
    );
    Future<Map<String, dynamic>> fetch(Uri uri) async => publicJwks;

    String sign(Map<String, dynamic> claims, {JsonWebKey? signer, String algorithm = 'RS256'}) {
      final builder = JsonWebSignatureBuilder()
        ..jsonContent = claims
        ..addRecipient(signer ?? key, algorithm: algorithm);
      return builder.build().toCompactSerialization();
    }

    Map<String, dynamic> claims({String? iss, String? aud, DateTime? exp, DateTime? iat, bool withIat = true}) {
      int seconds(DateTime d) => d.millisecondsSinceEpoch ~/ 1000;
      return {
        'iss': iss ?? clientId,
        'sub': clientId,
        'aud': aud ?? endpoint.toString(),
        'exp': seconds(exp ?? DateTime.now().add(const Duration(minutes: 4))),
        if (withIat) 'iat': seconds(iat ?? DateTime.now()),
        'jti': 'x',
      };
    }

    test('accepts an assertion signed by the client for this endpoint', () async {
      await verifyClientAssertion(sign(claims()), client, audiences: {endpoint.toString()}, fetch: fetch);
    });

    test('refuses a key the client did not publish', () async {
      final other = JsonWebKey.generate('RS256');
      await expectLater(
        verifyClientAssertion(
          sign(claims(), signer: other),
          client,
          audiences: {endpoint.toString()},
          fetch: fetch,
        ),
        throwsA(isA<OAuthError>()),
      );
    });

    test('accepts the issuer as the audience too', () async {
      await verifyClientAssertion(
        sign(claims(aud: 'https://site.example')),
        client,
        audiences: {endpoint.toString(), 'https://site.example'},
        fetch: fetch,
      );
    });

    test('refuses another audience or issuer, a bad lifetime, or no iat', () async {
      for (final bad in [
        claims(aud: 'https://elsewhere.example/token'),
        claims(iss: 'https://evil.example/meta.json'),
        claims(exp: DateTime.now().subtract(const Duration(minutes: 1))),
        claims(exp: DateTime.now().add(const Duration(days: 365))),
        claims(iat: DateTime.now().add(const Duration(hours: 1))),
        claims(withIat: false),
      ]) {
        await expectLater(
          verifyClientAssertion(sign(bad), client, audiences: {endpoint.toString()}, fetch: fetch),
          throwsA(isA<OAuthError>()),
        );
      }
    });

    test('refuses an unsigned assertion (alg none)', () async {
      String b64(Object o) => base64Url.encode(utf8.encode(jsonEncode(o))).replaceAll('=', '');
      final unsigned = '${b64({'alg': 'none'})}.${b64(claims())}.';
      await expectLater(
        verifyClientAssertion(unsigned, client, audiences: {endpoint.toString()}, fetch: fetch),
        throwsA(isA<OAuthError>()),
      );
    });
  });
}
