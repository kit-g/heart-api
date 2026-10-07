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

extension OAuthScopes on String? {
  /// Requested scopes, space-separated, narrowed to what this server grants
  /// (RFC 6749 §3.3: the server may issue fewer, and says so in the token
  /// response). Hosts add scopes of their own, such as `offline_access`;
  /// those are dropped, not refused. Absent asks for everything supported;
  /// asking only for scopes this server has never heard of is an error.
  List<String> toScopes() {
    final asked = (this ?? '').split(' ').where((s) => s.isNotEmpty).toSet();
    if (asked.isEmpty) return [...supportedScopes];
    final granted = asked.intersection(supportedScopes);
    if (granted.isEmpty) throw OAuthError('invalid_scope', 'none of these scopes exist here: ${asked.join(' ')}');
    return [...granted]..sort();
  }
}

extension OAuthResource on String {
  /// A resource identifier as compared: RFC 8707 says no trailing slash, and
  /// clients don't all agree.
  String toCanonicalResource() => endsWith('/') ? substring(0, length - 1) : this;
}

/// A client's metadata, as a stranger sent it: in a registration request or
/// a fetched Client ID Metadata Document.
extension ClientMetadata on Map<String, dynamic> {
  /// The RFC 7591 fields worth keeping. Whatever else a stranger sends isn't
  /// stored.
  Map<String, dynamic> toKnownClientMetadata() {
    const fields = {
      'client_id',
      'client_name',
      'client_uri',
      'logo_uri',
      'redirect_uris',
      'grant_types',
      'response_types',
      'token_endpoint_auth_method',
      'jwks_uri',
      'scope',
      'software_id',
      'software_version',
    };
    return {
      for (final MapEntry(:key, :value) in entries)
        if (fields.contains(key)) key: value,
    };
  }

  /// This, as the Client ID Metadata Document fetched from [url], checked:
  /// its `client_id` must be that URL, its redirects acceptable, its auth
  /// method one this server speaks.
  OAuthClient toClientDocument(Uri url, {required DateTime expiresAt}) {
    if (this['client_id'] != url.toString()) {
      throw const OAuthError('invalid_client', 'client_id in the metadata document must equal its URL');
    }
    final (redirects, auth, jwks) = _toClientShape();
    return OAuthClient(
      clientId: url.toString(),
      kind: .cimd,
      name: _toClientName(),
      redirectUris: redirects,
      auth: auth,
      jwksUri: jwks,
      expiresAt: expiresAt,
    );
  }

  /// This, as an RFC 7591 registration request, checked the same way, except
  /// that an auth method this server doesn't speak (a client secret) is
  /// replaced with `none`, as §3.2.1 allows; the response tells the client
  /// what it got.
  ({String? name, List<String> redirectUris, ClientAuth auth, Uri? jwksUri}) toRegistration() {
    final asked = {...this};
    if (ClientAuth.tryParse(asked['token_endpoint_auth_method']) == null) asked['token_endpoint_auth_method'] = 'none';
    final (redirects, auth, jwks) = asked._toClientShape(error: 'invalid_client_metadata');
    return (name: _toClientName(), redirectUris: redirects, auth: auth, jwksUri: jwks);
  }

  (List<String>, ClientAuth, Uri?) _toClientShape({String error = 'invalid_client'}) {
    final redirects = switch (this['redirect_uris']) {
      final List list when list.isNotEmpty && list.every((r) => r is String && isAcceptableRedirect(r)) =>
        list.cast<String>(),
      _ => throw OAuthError(error, 'redirect_uris must be https or loopback URLs'),
    };
    final auth =
        ClientAuth.tryParse(this['token_endpoint_auth_method']) ??
        (throw OAuthError(error, 'token_endpoint_auth_method must be none or private_key_jwt'));
    final jwks = switch ((auth, this['jwks_uri'])) {
      (.none, _) => null,
      (.privateKeyJwt, final String raw) when Uri.tryParse(raw)?.scheme == 'https' => Uri.parse(raw),
      _ => throw OAuthError(error, 'private_key_jwt needs an https jwks_uri'),
    };
    return (redirects, auth, jwks);
  }

  String? _toClientName() {
    return switch (this['client_name']) {
      final String name when name.trim().isNotEmpty =>
        name.trim().length > 100 ? name.trim().substring(0, 100) : name.trim(),
      _ => null,
    };
  }
}

extension ServerMetadata on OAuthConfig {
  /// The authorization server metadata (RFC 8414) the issuer serves. The
  /// site hosts it as a static file per environment; a test holds those
  /// files to this, so the document and the server can't drift apart.
  Map<String, dynamic> toServerMetadata() {
    return {
      'issuer': issuer.toString(),
      'authorization_endpoint': authorizationEndpoint.toString(),
      'token_endpoint': tokenEndpoint.toString(),
      'registration_endpoint': registrationEndpoint.toString(),
      'revocation_endpoint': revocationEndpoint.toString(),
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
}
