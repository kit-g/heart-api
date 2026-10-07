import 'package:heart/models/oauth.dart';
import 'package:heart/oauth/fetch.dart';
import 'package:heart/oauth/protocol.dart';
import 'package:jose/jose.dart';

/// How long a fetched metadata document is trusted before it's fetched
/// again: long enough that a popular host costs one fetch, short enough that
/// a client changing its redirects isn't held to the old ones for long.
const documentLifetime = Duration(hours: 1);

/// The client behind [clientId], or an [OAuthError] saying why there isn't
/// one. A URL is a Client ID Metadata Document, fetched and cached; anything
/// else must be a registration this server issued.
Future<OAuthClient> resolveClient(
  String clientId,
  OAuthService service,
  JsonFetch fetch, {
  DateTime? now,
}) async {
  final at = now ?? DateTime.now();
  final cached = await service.getClient(clientId);
  if (cached != null && cached.isFresh(at)) return cached;

  final url = Uri.tryParse(clientId);
  if (url == null || url.scheme != 'https') {
    throw const OAuthError('invalid_client', 'unknown client');
  }
  final Map<String, dynamic> document;
  try {
    document = await fetch(url);
  } on DocumentFetchError catch (e) {
    throw OAuthError('invalid_client', 'client metadata document: ${e.reason}');
  }
  final client = document.toClientDocument(url, expiresAt: at.add(documentLifetime));
  return service.saveClient(client, document.toKnownClientMetadata());
}

/// Signature algorithms a client assertion may use. Never `none`.
const _assertionAlgorithms = ['RS256', 'RS384', 'RS512', 'PS256', 'PS384', 'PS512', 'ES256', 'ES384', 'ES512'];

/// How far ahead an assertion's expiry may be. A short-lived assertion is
/// what keeps an unremembered `jti` from mattering for long.
const _assertionLifetime = Duration(minutes: 5);

/// Clock skew tolerated on `iat`.
const _skew = Duration(minutes: 1);

/// Verifies a `private_key_jwt` client assertion (RFC 7523 §3): signed by a
/// key from the client's `jwks_uri`, issued and subject to the client itself,
/// addressed to one of [audiences] (the issuer, or the endpoint being
/// called), issued now-ish, expiring within five minutes, and carrying a `jti`.
///
/// Returns the assertion's `jti` and expiry, for the caller to record: an
/// assertion is good once.
Future<({String jti, DateTime expiresAt})> verifyClientAssertion(
  String assertion,
  OAuthClient client, {
  required Set<String> audiences,
  required JsonFetch fetch,
  DateTime? now,
}) async {
  final jwksUri = client.jwksUri;
  if (client.auth != ClientAuth.privateKeyJwt || jwksUri == null) {
    throw const OAuthError('invalid_client', 'client does not authenticate with private_key_jwt', status: 401);
  }
  if (assertion.split('.').length != 3) {
    throw const OAuthError('invalid_client', 'client_assertion must be a signed JWT', status: 401);
  }

  final JsonWebToken token;
  try {
    final keys = await fetch(jwksUri);
    final store = JsonWebKeyStore()..addKeySet(JsonWebKeySet.fromJson(keys));
    token = await JsonWebToken.decodeAndVerify(assertion, store, allowedArguments: _assertionAlgorithms);
  } on Object {
    throw const OAuthError('invalid_client', 'client_assertion did not verify', status: 401);
  }

  final claims = token.claims;
  final at = now ?? DateTime.now();
  final valid =
      claims.issuer?.toString() == client.clientId &&
      claims.subject == client.clientId &&
      (claims.audience ?? const []).any(audiences.contains) &&
      switch ((claims.issuedAt, claims.expiry)) {
        (final DateTime issued, final DateTime expiry) =>
          !issued.isAfter(at.add(_skew)) && expiry.isAfter(at) && !expiry.isAfter(at.add(_assertionLifetime + _skew)),
        _ => false,
      };
  return switch ((valid, claims.jwtId, claims.expiry)) {
    (true, final String jti, final DateTime expiry) when jti.isNotEmpty => (jti: jti, expiresAt: expiry),
    _ => throw const OAuthError('invalid_client', 'client_assertion claims do not match this client', status: 401),
  };
}
