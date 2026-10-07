import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:heart/globals/config.dart';
import 'package:heart/models/oauth.dart';
import 'package:relic/relic.dart';

/// Scopes this server grants. `read` covers everything under `/me` and the
/// MCP server's read tools.
const supportedScopes = {'read'};

/// An OAuth protocol failure (RFC 6749 §5.2): the protocol's own error shape,
/// `{error, error_description}`, not the API's.
class OAuthError implements Exception {
  final String error;
  final String description;
  final int status;

  const new(this.error, this.description, {this.status = 400});

  Response toResponse({Headers? headers}) {
    return Response(
      status,
      body: Body.fromString(jsonEncode({'error': error, 'error_description': description}), mimeType: MimeType.json),
      headers: headers ?? Headers.build((h) => h.cacheControl = CacheControlHeader(noStore: true)),
    );
  }

  @override
  String toString() => 'OAuthError: $error ($description)';
}

/// PKCE S256 (RFC 7636): the verifier hashes to the challenge stored at
/// /authorize. Verifiers are 43–128 unreserved characters.
bool verifyPkce(String verifier, String challenge) {
  if (!RegExp(r'^[A-Za-z0-9\-._~]{43,128}$').hasMatch(verifier)) return false;
  final hashed = base64Url.encode(sha256.convert(ascii.encode(verifier)).bytes).replaceAll('=', '');
  return hashed == challenge;
}

/// Whether [requested] is one of [registered]: exactly, or, for a loopback
/// redirect, on any port (RFC 8252 §7.3), since native clients pick a free
/// port at run time.
bool redirectMatches(String requested, List<String> registered) {
  if (registered.contains(requested)) return true;
  final asked = Uri.tryParse(requested);
  if (asked == null || !_isLoopback(asked)) return false;
  return registered
      .map(Uri.tryParse)
      .any(
        (uri) =>
            uri != null &&
            _isLoopback(uri) &&
            uri.scheme == asked.scheme &&
            uri.host == asked.host &&
            uri.path == asked.path &&
            uri.query == asked.query,
      );
}

bool _isLoopback(Uri uri) => uri.scheme == 'http' && {'localhost', '127.0.0.1', '[::1]', '::1'}.contains(uri.host);

/// A redirect a client may register: https, or http to a loopback host.
/// Never with a fragment.
bool isAcceptableRedirect(String raw) {
  final uri = Uri.tryParse(raw);
  if (uri == null || uri.hasFragment || uri.host.isEmpty) return false;
  return uri.scheme == 'https' || _isLoopback(uri);
}

/// Requested scopes, space-separated. Absent asks for everything supported;
/// anything unsupported is refused rather than silently dropped.
List<String> parseScopes(String? raw) {
  final asked = (raw ?? '').split(' ').where((s) => s.isNotEmpty).toSet();
  if (asked.isEmpty) return [...supportedScopes];
  final unknown = asked.difference(supportedScopes);
  if (unknown.isNotEmpty) throw OAuthError('invalid_scope', 'unsupported scope: ${unknown.join(' ')}');
  return [...asked]..sort();
}

/// A Client ID Metadata Document, checked: its `client_id` must be the URL it
/// was fetched from, its redirects acceptable, its auth method one this
/// server speaks.
OAuthClient parseClientDocument(Uri url, Map<String, dynamic> document, {required DateTime expiresAt}) {
  if (document['client_id'] != url.toString()) {
    throw const OAuthError('invalid_client', 'client_id in the metadata document must equal its URL');
  }
  final (redirects, auth, jwks) = _clientShape(document);
  return OAuthClient(
    clientId: url.toString(),
    kind: .cimd,
    name: _name(document),
    redirectUris: redirects,
    auth: auth,
    jwksUri: jwks,
    expiresAt: expiresAt,
  );
}

/// An RFC 7591 registration request, checked the same way.
({String? name, List<String> redirectUris, ClientAuth auth, Uri? jwksUri}) parseRegistration(
  Map<String, dynamic> request,
) {
  final (redirects, auth, jwks) = _clientShape(request, error: 'invalid_client_metadata');
  return (name: _name(request), redirectUris: redirects, auth: auth, jwksUri: jwks);
}

(List<String>, ClientAuth, Uri?) _clientShape(Map<String, dynamic> json, {String error = 'invalid_client'}) {
  final redirects = switch (json['redirect_uris']) {
    final List list when list.isNotEmpty && list.every((r) => r is String && isAcceptableRedirect(r)) =>
      list.cast<String>(),
    _ => throw OAuthError(error, 'redirect_uris must be https or loopback URLs'),
  };
  final auth =
      ClientAuth.tryParse(json['token_endpoint_auth_method']) ??
      (throw OAuthError(error, 'token_endpoint_auth_method must be none or private_key_jwt'));
  final jwks = switch ((auth, json['jwks_uri'])) {
    (.none, _) => null,
    (.privateKeyJwt, final String raw) when Uri.tryParse(raw)?.scheme == 'https' => Uri.parse(raw),
    _ => throw OAuthError(error, 'private_key_jwt needs an https jwks_uri'),
  };
  return (redirects, auth, jwks);
}

String? _name(Map<String, dynamic> json) {
  return switch (json['client_name']) {
    final String name when name.trim().isNotEmpty =>
      name.trim().length > 100 ? name.trim().substring(0, 100) : name.trim(),
    _ => null,
  };
}

/// The authorization server metadata (RFC 8414) the issuer serves. The site
/// hosts it as a static file per environment; a test holds those files to
/// this, so the document and the server can't drift apart.
Map<String, dynamic> authorizationServerMetadata(OAuthConfig oauth) {
  return {
    'issuer': oauth.issuer.toString(),
    'authorization_endpoint': oauth.authorizationEndpoint.toString(),
    'token_endpoint': oauth.tokenEndpoint.toString(),
    'registration_endpoint': oauth.registrationEndpoint.toString(),
    'revocation_endpoint': oauth.revocationEndpoint.toString(),
    'scopes_supported': [...supportedScopes],
    'response_types_supported': ['code'],
    'grant_types_supported': ['authorization_code', 'refresh_token'],
    'code_challenge_methods_supported': ['S256'],
    'token_endpoint_auth_methods_supported': [for (final auth in ClientAuth.values) auth.value],
    'token_endpoint_auth_signing_alg_values_supported': ['RS256', 'PS256', 'ES256'],
    'revocation_endpoint_auth_methods_supported': [for (final auth in ClientAuth.values) auth.value],
    'client_id_metadata_document_supported': true,
    'authorization_response_iss_parameter_supported': true,
  };
}
