import 'dart:convert';

import 'package:heart/apple/client.dart';
import 'package:heart/globals/config.dart';
import 'package:pointycastle/export.dart';
import 'package:test/test.dart';

/// A throwaway P-256 key, generated for this file and used nowhere else. It
/// guards nothing — its only job is to be a real PKCS#8 `.p8` of the shape
/// Apple issues, so the parser is exercised against the genuine encoding.
const _pem = '''
-----BEGIN PRIVATE KEY-----
MIGHAgEAMBMGByqGSM49AgEGCCqGSM49AwEHBG0wawIBAQQgf9YXACvdy/cO+3RZ
LZCTWxssIc62l/V8GT77B2L1qUChRANCAARYqn0aXxNVHZXjmIhBpvmjCcSqKcxi
nSgpIQ+0EPgl0ElpWKsSBX5jgkTpv9+86ukWNnTT3HumV3EuxDSL42nU
-----END PRIVATE KEY-----
''';

/// The public point `openssl ec -text` reports for [_pem]. Deriving this from
/// the parsed scalar and comparing is what proves the parser read the right
/// bytes — without it, a wrong scalar would still sign and still verify
/// against itself.
const _publicX = '58aa7d1a5f13551d95e3988841a6f9a309c4aa29cc629d2829210fb410f825d0';
const _publicY = '496958ab12057e638244e9bfdfbceae9163674d3dc7ba657712ec4348be369d4';

const _bundleId = 'me.heart-of.ios';
const _servicesId = 'me.heart-of.web';

AppleConfig _config() {
  return const AppleConfig(
    teamId: 'TEAM123456',
    keyId: 'KEY1234567',
    privateKey: _pem,
    clients: {_bundleId: null, _servicesId: 'https://heart-of.me/apple'},
  );
}

/// Records what the client posted and answers with a canned response.
class _Transport {
  final int status;
  final String body;
  final Object? throws;

  Uri? uri;
  Map<String, String>? form;
  var calls = 0;

  new({this.status = 200, this.body = '{}', this.throws});

  Future<(int, String)> call(Uri uri, Map<String, String> form) async {
    calls++;
    this.uri = uri;
    this.form = form;
    if (throws case final Object e) throw e;
    return (status, body);
  }
}

Map<String, dynamic> _segment(String s) {
  return jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(s)))) as Map<String, dynamic>;
}

void main() {
  group('AppleSignInKey', () {
    final key = AppleSignInKey.parse(pem: _pem, teamId: 'TEAM123456', keyId: 'KEY1234567');

    test('rejects something that is not a PKCS#8 key', () {
      expect(
        () => AppleSignInKey.parse(pem: 'not a key', teamId: 'T', keyId: 'K'),
        throwsA(isA<Exception>()),
      );
    });

    test('signs a client secret Apple would accept', () {
      final issuedAt = DateTime.utc(2026, 9, 19, 12);
      final secret = key.clientSecretFor(_bundleId, issuedAt: issuedAt);
      final [header, payload, signature] = secret.split('.');

      expect(_segment(header), {'alg': 'ES256', 'kid': 'KEY1234567'});
      expect(_segment(payload), {
        'iss': 'TEAM123456',
        'iat': issuedAt.millisecondsSinceEpoch ~/ 1000,
        'exp': issuedAt.add(const Duration(minutes: 5)).millisecondsSinceEpoch ~/ 1000,
        'aud': 'https://appleid.apple.com',
        'sub': _bundleId,
      });

      // JWS carries the raw r||s pair, 32 bytes each — not DER.
      expect(base64Url.decode(base64Url.normalize(signature)), hasLength(64));
    });

    // The oracle for the parser too: a scalar read wrong out of the PKCS#8
    // wrapper still signs, and still verifies against itself — only the
    // public point openssl independently reports catches it.
    test('the signature verifies under the matching public key', () {
      final secret = key.clientSecretFor(_bundleId);
      final [header, payload, signature] = secret.split('.');
      final raw = base64Url.decode(base64Url.normalize(signature));

      final curve = ECCurve_prime256v1();
      final verifier = ECDSASigner(SHA256Digest())
        ..init(
          false,
          PublicKeyParameter<ECPublicKey>(
            ECPublicKey(
              curve.curve.createPoint(
                BigInt.parse(_publicX, radix: 16),
                BigInt.parse(_publicY, radix: 16),
              ),
              curve,
            ),
          ),
        );

      expect(
        verifier.verifySignature(
          utf8.encode('$header.$payload'),
          ECSignature(
            BigInt.parse(raw.take(32).map((b) => b.toRadixString(16).padLeft(2, '0')).join(), radix: 16),
            BigInt.parse(raw.skip(32).map((b) => b.toRadixString(16).padLeft(2, '0')).join(), radix: 16),
          ),
        ),
        isTrue,
      );
    });

    test('a secret is bound to the client that asked for it', () {
      expect(_segment(key.clientSecretFor(_servicesId).split('.')[1])['sub'], _servicesId);
    });
  });

  group('exchangeAuthorizationCode', () {
    test('returns the refresh token and posts the code exchange', () async {
      final transport = _Transport(body: '{"refresh_token":"r-token","access_token":"a"}');
      final apple = AppleIdentity(config: _config(), transport: transport.call);

      expect(await apple.exchangeAuthorizationCode(code: 'c0de', clientId: _bundleId), 'r-token');
      expect(transport.uri.toString(), 'https://appleid.apple.com/auth/token');
      expect(transport.form, containsPair('grant_type', 'authorization_code'));
      expect(transport.form, containsPair('code', 'c0de'));
      expect(transport.form, containsPair('client_id', _bundleId));
      expect(transport.form!['client_secret'], isNotEmpty);
    });

    test('a native client sends no redirect_uri; the web one does', () async {
      final native = _Transport(body: '{"refresh_token":"r"}');
      await AppleIdentity(config: _config(), transport: native.call) //
          .exchangeAuthorizationCode(code: 'c', clientId: _bundleId);
      expect(native.form, isNot(contains('redirect_uri')));

      final web = _Transport(body: '{"refresh_token":"r"}');
      await AppleIdentity(config: _config(), transport: web.call) //
          .exchangeAuthorizationCode(code: 'c', clientId: _servicesId);
      expect(web.form, containsPair('redirect_uri', 'https://heart-of.me/apple'));
    });

    test('an unconfigured client never reaches Apple', () async {
      final transport = _Transport();
      final apple = AppleIdentity(config: _config(), transport: transport.call);

      expect(await apple.exchangeAuthorizationCode(code: 'c', clientId: 'me.someone.else'), isNull);
      expect(transport.calls, 0);
    });

    test('a refusal is null, not a throw', () async {
      final transport = _Transport(status: 400, body: '{"error":"invalid_grant"}');
      final apple = AppleIdentity(config: _config(), transport: transport.call);

      expect(await apple.exchangeAuthorizationCode(code: 'stale', clientId: _bundleId), isNull);
    });

    test('a 200 without a refresh token is null', () async {
      final transport = _Transport(body: '{"access_token":"a"}');
      final apple = AppleIdentity(config: _config(), transport: transport.call);

      expect(await apple.exchangeAuthorizationCode(code: 'c', clientId: _bundleId), isNull);
    });

    test('a transport that throws is null', () async {
      final transport = _Transport(throws: const SocketExceptionStub());
      final apple = AppleIdentity(config: _config(), transport: transport.call);

      expect(await apple.exchangeAuthorizationCode(code: 'c', clientId: _bundleId), isNull);
    });
  });

  group('revokeGrant', () {
    test('posts the refresh token with its hint', () async {
      final transport = _Transport(body: '');
      final apple = AppleIdentity(config: _config(), transport: transport.call);

      await apple.revokeGrant(refreshToken: 'r-token', clientId: _bundleId);

      expect(transport.uri.toString(), 'https://appleid.apple.com/auth/revoke');
      expect(transport.form, containsPair('token', 'r-token'));
      expect(transport.form, containsPair('token_type_hint', 'refresh_token'));
      expect(transport.form, containsPair('client_id', _bundleId));
    });

    // Every one of these is a deletion that has to go through anyway.
    for (final (name, transport) in [
      ('an already-revoked token', _Transport(status: 400, body: '{"error":"invalid_grant"}')),
      ('Apple being down', _Transport(status: 503, body: 'nope')),
      ('a network failure', _Transport(throws: const SocketExceptionStub())),
      ('an unconfigured client', _Transport()),
    ]) {
      test('$name does not throw', () {
        final clientId = name == 'an unconfigured client' ? 'me.someone.else' : _bundleId;
        final apple = AppleIdentity(config: _config(), transport: transport.call);

        expect(apple.revokeGrant(refreshToken: 'r', clientId: clientId), completes);
      });
    }
  });
}

class SocketExceptionStub implements Exception {
  const new();
}
