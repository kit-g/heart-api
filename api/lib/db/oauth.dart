part of 'db.dart';

/// How long after a refresh token's rotation presenting it again counts as a
/// host's retry rather than theft.
const reuseGrace = Duration(minutes: 1);

mixin _OAuth on _DatabaseBase implements OAuthService {
  @override
  Future<OAuthClient?> getClient(String clientId) async {
    final rows = await _pool.execute(_getOAuthClient.toSql(), parameters: {'clientId': clientId});
    if (rows.isEmpty) return null;
    return OAuthClient.fromRow(rows.first.toColumnMap());
  }

  @override
  Future<OAuthClient> saveClient(OAuthClient client, Map<String, dynamic> metadata) async {
    final rows = await _pool.execute(
      _saveOAuthClient.toSql(),
      parameters: {
        'clientId': client.clientId,
        'name': client.name,
        'redirectUris': client.redirectUris,
        'auth': client.auth.value,
        'jwksUri': client.jwksUri?.toString(),
        'metadata': jsonEncode(metadata),
        'expiresAt': client.expiresAt?.toUtc(),
      },
    );
    return OAuthClient.fromRow(rows.first.toColumnMap());
  }

  @override
  Future<OAuthClient> registerClient({
    String? name,
    required List<String> redirectUris,
    required ClientAuth auth,
    Uri? jwksUri,
    required Map<String, dynamic> metadata,
  }) async {
    final rows = await _pool.execute(
      _registerOAuthClient.toSql(),
      parameters: {
        'name': name,
        'redirectUris': redirectUris,
        'auth': auth.value,
        'jwksUri': jwksUri?.toString(),
        'metadata': jsonEncode(metadata),
      },
    );
    return OAuthClient.fromRow(rows.first.toColumnMap());
  }

  @override
  Future<String> createRequest({
    required String clientId,
    required String redirectUri,
    required String codeChallenge,
    required List<String> scopes,
    required String resource,
    String? state,
    required Duration ttl,
  }) async {
    final rows = await _pool.execute(
      _createOAuthRequest.toSql(),
      parameters: {
        'clientId': clientId,
        'redirectUri': redirectUri,
        'codeChallenge': codeChallenge,
        'scopes': scopes,
        'resource': resource,
        'state': state,
        'ttlSeconds': ttl.inSeconds,
      },
    );
    return rows.first.toColumnMap()['id'].toString();
  }

  @override
  Future<AuthorizationRequest?> getPendingRequest(String requestId) {
    return _oneRequest(_getPendingOAuthRequest, {'requestId': requestId});
  }

  @override
  Future<AuthorizationRequest?> approveRequest({
    required String requestId,
    required String userId,
    required Uint8List codeHash,
    required Duration codeTtl,
  }) {
    return _oneRequest(_approveOAuthRequest, {
      'requestId': requestId,
      'userId': userId,
      'codeHash': codeHash,
      'codeTtlSeconds': codeTtl.inSeconds,
    });
  }

  @override
  Future<AuthorizationRequest?> denyRequest(String requestId) {
    return _oneRequest(_denyOAuthRequest, {'requestId': requestId});
  }

  Future<AuthorizationRequest?> _oneRequest(String sql, Map<String, dynamic> parameters) async {
    final rows = await _pool.execute(sql.toSql(), parameters: parameters);
    if (rows.isEmpty) return null;
    return AuthorizationRequest.fromRow(rows.first.toColumnMap());
  }

  @override
  Future<RedeemedCode?> redeemCode(Uint8List codeHash) async {
    final rows = await _pool.execute(_redeemOAuthCode.toSql(), parameters: {'codeHash': codeHash});
    if (rows.isEmpty) return null;
    final row = rows.first.toColumnMap();
    return (
      userId: row['user_id'] as String,
      clientId: row['client_id'] as String,
      redirectUri: row['redirect_uri'] as String,
      codeChallenge: row['code_challenge'] as String,
      scopes: [...(row['scopes'] as List).cast<String>()],
      resource: row['resource'] as String,
    );
  }

  @override
  Future<bool> rememberAssertion({required String clientId, required String jti, required DateTime expiresAt}) async {
    final rows = await _pool.execute(
      _rememberOAuthAssertion.toSql(),
      parameters: {'clientId': clientId, 'jti': jti, 'expiresAt': expiresAt.toUtc()},
    );
    return rows.isNotEmpty;
  }

  @override
  Future<int> countRegistration(String address) async {
    final rows = await _pool.execute(_countOAuthRegistration.toSql(), parameters: {'address': address});
    return rows.single.toColumnMap()['count'] as int;
  }

  @override
  Future<bool> issueTokens({
    required String userId,
    required String clientId,
    required String resource,
    required List<String> scopes,
    required TokenPair tokens,
  }) async {
    final rows = await _pool.execute(
      _issueOAuthTokens.toSql(),
      parameters: {
        'userId': userId,
        'clientId': clientId,
        'resource': resource,
        'scopes': scopes,
        ..._tokenParameters(tokens),
        'refreshHash': tokens.refreshHash,
      },
    );
    return rows.isNotEmpty;
  }

  @override
  Future<({RefreshOutcome outcome, List<String> scopes})> rotateRefreshToken({
    required Uint8List refreshHash,
    required String clientId,
    required TokenPair tokens,
  }) async {
    final rows = await _pool.execute(
      _rotateOAuthRefresh.toSql(),
      parameters: {
        'refreshHash': refreshHash,
        'clientId': clientId,
        ..._tokenParameters(tokens),
        'newRefreshHash': tokens.refreshHash,
        'graceSeconds': reuseGrace.inSeconds,
      },
    );
    final row = rows.first.toColumnMap();
    return (
      outcome: RefreshOutcome.values.byName(row['outcome'] as String),
      scopes: [...?(row['scopes'] as List?)?.cast<String>()],
    );
  }

  Map<String, dynamic> _tokenParameters(TokenPair tokens) {
    return {
      'accessHash': tokens.accessHash,
      'accessHint': tokens.accessHint,
      'accessExpiresAt': tokens.accessExpiresAt.toUtc(),
      'refreshExpiresAt': tokens.refreshExpiresAt.toUtc(),
    };
  }

  @override
  Future<void> revokeOAuthToken({required Uint8List tokenHash, required String clientId}) async {
    await _pool.execute(_revokeOAuthToken.toSql(), parameters: {'tokenHash': tokenHash, 'clientId': clientId});
  }

  @override
  Future<List<ConnectedApp>> listConnectedApps(String userId) async {
    final rows = await _pool.execute(_listConnectedApps.toSql(), parameters: {'userId': userId});
    return [for (final row in rows) ConnectedApp.fromRow(row.toColumnMap())];
  }

  @override
  Future<bool> disconnectApp({required String userId, required String grantId}) async {
    final rows = await _pool.execute(_disconnectApp.toSql(), parameters: {'userId': userId, 'grantId': grantId});
    return rows.isNotEmpty;
  }
}
