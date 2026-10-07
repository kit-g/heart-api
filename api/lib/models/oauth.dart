import 'dart:typed_data';

import 'package:heart_models/heart_models.dart';

/// How a client proves itself at the token endpoint.
enum ClientAuth {
  /// A public client: PKCE alone.
  none('none'),

  /// Signs an assertion with a key from its `jwks_uri` (RFC 7523).
  privateKeyJwt('private_key_jwt');

  /// The RFC 7591 wire value.
  final String value;

  new(this.value);

  static ClientAuth? tryParse(Object? v) {
    return switch (v) {
      null || 'none' => none,
      'private_key_jwt' => privateKeyJwt,
      _ => null,
    };
  }
}

enum ClientKind { cimd, dcr }

/// A client that may ask for authorization.
class OAuthClient {
  final String clientId;
  final ClientKind kind;
  final String? name;
  final List<String> redirectUris;
  final ClientAuth auth;
  final Uri? jwksUri;

  /// When a cached metadata document must be fetched again; null for a
  /// registration, which doesn't expire.
  final DateTime? expiresAt;

  const new({
    required this.clientId,
    required this.kind,
    this.name,
    required this.redirectUris,
    this.auth = .none,
    this.jwksUri,
    this.expiresAt,
  });

  bool isFresh([DateTime? now]) => expiresAt == null || expiresAt!.isAfter(now ?? DateTime.now());

  /// What the consent screen calls the client: its own name, or its id.
  String get displayName => name ?? clientId;

  factory fromRow(Map<String, dynamic> row) {
    return OAuthClient(
      clientId: row['client_id'] as String,
      kind: ClientKind.values.byName(row['kind'] as String),
      name: row['client_name'] as String?,
      redirectUris: [...(row['redirect_uris'] as List).cast<String>()],
      auth: ClientAuth.tryParse(row['token_endpoint_auth_method']) ?? .none,
      jwksUri: switch (row['jwks_uri']) {
        final String uri => Uri.parse(uri),
        _ => null,
      },
      expiresAt: row['expires_at'] as DateTime?,
    );
  }
}

/// An authorization request awaiting the account's answer.
class AuthorizationRequest {
  final String id;
  final String clientId;
  final String clientName;
  final Uri redirectUri;
  final List<String> scopes;
  final String resource;
  final String? state;

  const new({
    required this.id,
    required this.clientId,
    required this.clientName,
    required this.redirectUri,
    required this.scopes,
    required this.resource,
    this.state,
  });

  factory fromRow(Map<String, dynamic> row) {
    return AuthorizationRequest(
      id: row['id'].toString(),
      clientId: row['client_id'] as String,
      clientName: (row['client_name'] as String?) ?? row['client_id'] as String,
      redirectUri: Uri.parse(row['redirect_uri'] as String),
      scopes: [...(row['scopes'] as List).cast<String>()],
      resource: row['resource'] as String,
      state: row['state'] as String?,
    );
  }
}

/// An authorization code, redeemed: everything the token endpoint checks
/// before issuing.
typedef RedeemedCode = ({
  String userId,
  String clientId,
  String redirectUri,
  String codeChallenge,
  List<String> scopes,
  String resource,
});

/// Fresh tokens for a grant, as hashes and the times they lapse. The
/// plaintexts never reach the database.
typedef TokenPair = ({
  Uint8List accessHash,
  String accessHint,
  DateTime accessExpiresAt,
  Uint8List refreshHash,
  DateTime refreshExpiresAt,
});

/// What a refresh token turned out to be.
enum RefreshOutcome {
  /// Exchanged for a new pair.
  rotated,

  /// Already exchanged once: someone else holds a copy, and the grant is now
  /// revoked.
  reused,

  /// Unknown, expired, revoked, another client's, or presented again within
  /// a minute of its rotation (a retry, refused without revoking).
  invalid,
}

abstract interface class OAuthService {
  Future<OAuthClient?> getClient(String clientId);

  /// Stores a fetched metadata document, replacing an older copy.
  Future<OAuthClient> saveClient(OAuthClient client, Map<String, dynamic> metadata);

  /// Stores a dynamic registration and returns it with its new id.
  Future<OAuthClient> registerClient({
    String? name,
    required List<String> redirectUris,
    required ClientAuth auth,
    Uri? jwksUri,
    required Map<String, dynamic> metadata,
  });

  /// Opens an authorization request and returns its id.
  Future<String> createRequest({
    required String clientId,
    required String redirectUri,
    required String codeChallenge,
    required List<String> scopes,
    required String resource,
    String? state,
    required Duration ttl,
  });

  /// A request still waiting for an answer; null once answered or expired.
  Future<AuthorizationRequest?> getPendingRequest(String requestId);

  /// Approves a pending request as [userId]: records or widens the grant and
  /// stores the code's hash. Null when the request isn't pending.
  Future<AuthorizationRequest?> approveRequest({
    required String requestId,
    required String userId,
    required Uint8List codeHash,
    required Duration codeTtl,
  });

  /// Refuses a pending request. Null when it isn't pending.
  Future<AuthorizationRequest?> denyRequest(String requestId);

  /// Spends an authorization code. Null when it is unknown, expired or spent.
  Future<RedeemedCode?> redeemCode(Uint8List codeHash);

  /// Issues the first token pair under the live grant for [userId], [clientId]
  /// and [resource]. False when there is no such grant.
  Future<bool> issueTokens({
    required String userId,
    required String clientId,
    required String resource,
    required List<String> scopes,
    required TokenPair tokens,
  });

  /// Exchanges a refresh token for a new pair, or detects its reuse.
  Future<({RefreshOutcome outcome, List<String> scopes})> rotateRefreshToken({
    required Uint8List refreshHash,
    required String clientId,
    required TokenPair tokens,
  });

  /// RFC 7009 revocation by the client itself: an access token goes alone,
  /// a refresh token takes its grant with it.
  Future<void> revokeOAuthToken({required Uint8List tokenHash, required String clientId});

  Future<List<ConnectedApp>> listConnectedApps(String userId);

  /// Revokes one of [userId]'s grants and every token under it. False when
  /// there is no such live grant.
  Future<bool> disconnectApp({required String userId, required String grantId});
}
