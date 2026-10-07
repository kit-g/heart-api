import 'dart:convert';

import 'package:heart/core/response.dart';
import 'package:heart/globals/config.dart';
import 'package:heart/globals/globals.dart';
import 'package:heart/middleware/database.dart';
import 'package:heart/models/errors.dart';
import 'package:heart/models/oauth.dart';
import 'package:heart/models/tokens.dart';
import 'package:heart/oauth/clients.dart';
import 'package:heart/middleware/oauth.dart';
import 'package:heart/oauth/protocol.dart';
import 'package:heart_models/heart_models.dart';
import 'package:relic/relic.dart';

/// How long the account has to answer the consent screen.
const _requestLifetime = Duration(minutes: 10);

/// How long an authorization code is good for.
const _codeLifetime = Duration(minutes: 1);

/// Access tokens are short; the refresh token carries the session.
const _accessLifetime = Duration(hours: 1);

/// A host unused this long asks the account again.
const _refreshLifetime = Duration(days: 90);

const _assertionType = 'urn:ietf:params:oauth:client-assertion-type:jwt-bearer';

/// `GET /oauth/authorize`: validates the request and hands the browser to the
/// consent page. Until the client and its redirect check out, errors are
/// shown here; after, they go back to the client, as RFC 6749 §4.1.2.1 asks,
/// so nobody can use this endpoint to bounce a browser to an unverified URL.
Future<Response> authorize(Request req) async {
  final oauth = req.config.oauth;
  if (oauth == null) return JsonResponse.noSuchRoute();
  final q = req.url.queryParameters;

  final OAuthClient client;
  try {
    client = await resolveClient(q['client_id'] ?? '', req.oauthService, req.jsonFetch);
  } on OAuthError catch (e) {
    return e.toResponse();
  }
  final redirect = q['redirect_uri'] ?? '';
  if (!redirectMatches(redirect, client.redirectUris)) {
    return const OAuthError('invalid_request', 'redirect_uri is not registered for this client').toResponse();
  }

  Response back(OAuthError e) {
    return _redirect(Uri.parse(redirect), oauth, {
      'error': e.error,
      'error_description': e.description,
      'state': ?q['state'],
    });
  }

  if (q['response_type'] != 'code') {
    return back(const OAuthError('unsupported_response_type', 'response_type must be code'));
  }
  final challenge = q['code_challenge'] ?? '';
  if (q['code_challenge_method'] != 'S256' || !RegExp(r'^[A-Za-z0-9_-]{43}$').hasMatch(challenge)) {
    return back(const OAuthError('invalid_request', 'PKCE with S256 is required'));
  }
  final resource = q['resource'] ?? '';
  if (!oauth.resources.contains(resource)) {
    return back(const OAuthError('invalid_target', 'resource must be this server\'s MCP or /me surface'));
  }
  final List<String> scopes;
  try {
    scopes = parseScopes(q['scope']);
  } on OAuthError catch (e) {
    return back(e);
  }

  final requestId = await req.oauthService.createRequest(
    clientId: client.clientId,
    redirectUri: redirect,
    codeChallenge: challenge,
    scopes: scopes,
    resource: resource,
    state: q['state'],
    ttl: _requestLifetime,
  );
  return Response(302, headers: Headers.build((h) => h.location = oauth.consentPage(requestId)));
}

/// `POST /oauth/token` (form-encoded): authorization code and refresh token
/// grants.
Future<Response> token(Request req) async {
  final oauth = req.config.oauth;
  if (oauth == null) return JsonResponse.noSuchRoute();
  try {
    final form = await _form(req);
    final client = await _authenticateClient(req, form, oauth);
    final tokens = _mint();
    final List<String> scopes;

    switch (form['grant_type']) {
      case 'authorization_code':
        final code = await req.oauthService.redeemCode(TokenSecret.hash(form['code'] ?? ''));
        final valid =
            code != null &&
            code.clientId == client.clientId &&
            code.redirectUri == form['redirect_uri'] &&
            verifyPkce(form['code_verifier'] ?? '', code.codeChallenge) &&
            switch (form['resource']) {
              null || '' => true,
              final String resource => resource == code.resource,
            };
        if (!valid) throw const OAuthError('invalid_grant', 'code is invalid, expired, spent, or not this client\'s');
        final issued = await req.oauthService.issueTokens(
          userId: code.userId,
          clientId: code.clientId,
          resource: code.resource,
          scopes: code.scopes,
          tokens: tokens.pair,
        );
        if (!issued) throw const OAuthError('invalid_grant', 'the grant was revoked');
        scopes = code.scopes;

      case 'refresh_token':
        final rotated = await req.oauthService.rotateRefreshToken(
          refreshHash: TokenSecret.hash(form['refresh_token'] ?? ''),
          clientId: client.clientId,
          tokens: tokens.pair,
        );
        if (rotated.outcome != RefreshOutcome.rotated) {
          throw const OAuthError('invalid_grant', 'refresh token is invalid, expired or revoked');
        }
        scopes = rotated.scopes;

      default:
        throw const OAuthError('unsupported_grant_type', 'grant_type must be authorization_code or refresh_token');
    }

    return Response.ok(
      body: Body.fromString(
        jsonEncode({
          'access_token': tokens.access,
          'token_type': 'Bearer',
          'expires_in': _accessLifetime.inSeconds,
          'refresh_token': tokens.refresh,
          'scope': scopes.join(' '),
        }),
        mimeType: MimeType.json,
      ),
      headers: Headers.build((h) => h.cacheControl = CacheControlHeader(noStore: true)),
    );
  } on OAuthError catch (e) {
    return e.toResponse();
  }
}

/// `POST /oauth/register`: RFC 7591 dynamic registration, kept for clients
/// that don't do metadata documents.
Future<Response> register(Request req) async {
  if (req.config.oauth == null) return JsonResponse.noSuchRoute();
  try {
    final body = switch (jsonDecode(await req.readAsString())) {
      final Map<String, dynamic> json => json,
      _ => throw const OAuthError('invalid_client_metadata', 'expected a JSON object'),
    };
    final shape = parseRegistration(body);
    final client = await req.oauthService.registerClient(
      name: shape.name,
      redirectUris: shape.redirectUris,
      auth: shape.auth,
      jwksUri: shape.jwksUri,
      metadata: body,
    );
    return Response(
      201,
      body: Body.fromString(
        jsonEncode({
          'client_id': client.clientId,
          'client_id_issued_at': DateTime.now().millisecondsSinceEpoch ~/ 1000,
          'client_name': ?client.name,
          'redirect_uris': client.redirectUris,
          'token_endpoint_auth_method': client.auth.value,
          'jwks_uri': ?client.jwksUri?.toString(),
          'grant_types': const ['authorization_code', 'refresh_token'],
          'response_types': const ['code'],
        }),
        mimeType: MimeType.json,
      ),
      headers: Headers.build((h) => h.cacheControl = CacheControlHeader(noStore: true)),
    );
  } on FormatException {
    return const OAuthError('invalid_client_metadata', 'expected a JSON object').toResponse();
  } on OAuthError catch (e) {
    return e.toResponse();
  }
}

/// `POST /oauth/revoke` (RFC 7009): always 200, whether or not the token was
/// known, so the endpoint can't be used to probe for live tokens.
Future<Response> revoke(Request req) async {
  final oauth = req.config.oauth;
  if (oauth == null) return JsonResponse.noSuchRoute();
  try {
    final form = await _form(req);
    final client = await _authenticateClient(req, form, oauth);
    await req.oauthService.revokeOAuthToken(
      tokenHash: TokenSecret.hash(form['token'] ?? ''),
      clientId: client.clientId,
    );
    return Response.ok();
  } on OAuthError catch (e) {
    return e.toResponse();
  }
}

/// What the consent page shows.
class ConsentRequest implements Model {
  final AuthorizationRequest request;
  final OAuthConfig oauth;

  const new(this.request, this.oauth);

  @override
  Map<String, dynamic> toMap() {
    return {
      'id': request.id,
      'client': {'id': request.clientId, 'name': request.clientName},
      // shown prominently: a look-alike name can't fake where the code goes
      'redirectHost': request.redirectUri.host,
      'scopes': request.scopes,
      'resource': request.resource == oauth.mcpResource ? 'mcp' : 'me',
    };
  }
}

/// Where the consent page sends the browser next.
class ConsentRedirect implements Model {
  final Uri redirect;

  const new(this.redirect);

  @override
  Map<String, dynamic> toMap() => {'redirect': redirect.toString()};
}

/// `GET /oauth/requests/:requestId` (Firebase): the request awaiting an answer.
Future<ConsentRequest> getConsentRequest(Request req) async {
  final oauth = req.config.oauth ?? (throw const NotFound(type: 'oauth', id: 'disabled'));
  final id = _requestId(req);
  final request = await req.oauthService.getPendingRequest(id) ?? (throw NotFound(type: 'request', id: id));
  return ConsentRequest(request, oauth);
}

/// `POST /oauth/requests/:requestId/approve` (Firebase): records the grant and
/// mints the code.
Future<ConsentRedirect> approveConsentRequest(Request req) async {
  final oauth = req.config.oauth ?? (throw const NotFound(type: 'oauth', id: 'disabled'));
  final id = _requestId(req);
  final code = TokenSecret.random();
  final request =
      await req.oauthService.approveRequest(
        requestId: id,
        userId: req.userId,
        codeHash: TokenSecret.hash(code),
        codeTtl: _codeLifetime,
      ) ??
      (throw NotFound(type: 'request', id: id));
  return ConsentRedirect(_withQuery(request.redirectUri, oauth, {'code': code, 'state': ?request.state}));
}

/// `POST /oauth/requests/:requestId/deny` (Firebase).
Future<ConsentRedirect> denyConsentRequest(Request req) async {
  final oauth = req.config.oauth ?? (throw const NotFound(type: 'oauth', id: 'disabled'));
  final id = _requestId(req);
  final request = await req.oauthService.denyRequest(id) ?? (throw NotFound(type: 'request', id: id));
  return ConsentRedirect(
    _withQuery(request.redirectUri, oauth, {
      'error': 'access_denied',
      'error_description': 'the account declined',
      'state': ?request.state,
    }),
  );
}

class ConnectedAppsResponse implements Model {
  final List<ConnectedApp> apps;

  const new(this.apps);

  @override
  Map<String, dynamic> toMap() => {
    'apps': [for (final app in apps) app.toMap()],
  };
}

/// `GET /accounts/connected-apps`.
Future<ConnectedAppsResponse> listConnectedApps(Request req) async {
  return ConnectedAppsResponse(await req.oauthService.listConnectedApps(req.userId));
}

/// `DELETE /accounts/connected-apps/:grantId`.
Future<Model> disconnectApp(Request req) => disconnectAppById(req, req.rawPathParameters[#grantId]!);

Future<Model> disconnectAppById(Request req, String grantId) async {
  if (!isUuidV7(grantId) || !await req.oauthService.disconnectApp(userId: req.userId, grantId: grantId)) {
    throw NotFound(type: 'connected app', id: grantId);
  }
  throw const NoContent();
}

String _requestId(Request req) {
  final id = req.rawPathParameters[#requestId]!;
  if (!isUuidV7(id)) throw NotFound(type: 'request', id: id);
  return id;
}

Response _redirect(Uri to, OAuthConfig oauth, Map<String, String> params) {
  return Response(302, headers: Headers.build((h) => h.location = _withQuery(to, oauth, params)));
}

/// [to] with [params] and the issuer (RFC 9207) added to whatever query it
/// already had.
Uri _withQuery(Uri to, OAuthConfig oauth, Map<String, String> params) {
  return to.replace(queryParameters: {...to.queryParameters, ...params, 'iss': oauth.issuer.toString()});
}

/// A form-encoded body, as the token and revocation endpoints take.
Future<Map<String, String>> _form(Request req) async {
  if (req.mimeType?.primaryType != 'application' || req.mimeType?.subType != 'x-www-form-urlencoded') {
    throw const OAuthError('invalid_request', 'expected application/x-www-form-urlencoded');
  }
  try {
    return Uri.splitQueryString(await req.readAsString());
  } on FormatException {
    throw const OAuthError('invalid_request', 'malformed form body');
  }
}

/// Who is calling the token or revocation endpoint: a public client by its
/// `client_id`, or a `private_key_jwt` client by its signed assertion.
Future<OAuthClient> _authenticateClient(Request req, Map<String, String> form, OAuthConfig oauth) async {
  final assertion = form['client_assertion'];
  final id = form['client_id'] ?? '';
  final client = await resolveClient(id, req.oauthService, req.jsonFetch);
  switch ((client.auth, assertion)) {
    case (.none, null):
      return client;
    case (.privateKeyJwt, final String jwt) when form['client_assertion_type'] == _assertionType:
      await verifyClientAssertion(jwt, client, tokenEndpoint: oauth.tokenEndpoint, fetch: req.jsonFetch);
      return client;
    default:
      throw const OAuthError('invalid_client', 'client authentication failed', status: 401);
  }
}

/// A fresh access/refresh pair: the plaintexts for the response, the hashes
/// for the database.
({String access, String refresh, TokenPair pair}) _mint() {
  final access = TokenSecret.mint(prefix: TokenSecret.accessPrefix);
  final refresh = TokenSecret.mint(prefix: TokenSecret.refreshPrefix);
  final now = DateTime.now();
  return (
    access: access,
    refresh: refresh,
    pair: (
      accessHash: TokenSecret.hash(access),
      accessHint: TokenSecret.hint(access),
      accessExpiresAt: now.add(_accessLifetime),
      refreshHash: TokenSecret.hash(refresh),
      refreshExpiresAt: now.add(_refreshLifetime),
    ),
  );
}
