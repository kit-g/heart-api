part of 'db.dart';

mixin _ApiTokens on _DatabaseBase implements ApiTokenService {
  @override
  Future<ApiToken?> createToken({
    required String userId,
    required String name,
    ApiTokenPurpose? purpose,
    DateTime? expiresAt,
    required Uint8List tokenHash,
    required String hint,
  }) async {
    final result = await _pool.execute(
      _createApiToken.toSql(),
      parameters: {
        'userId': userId,
        'name': name,
        'purpose': purpose?.name,
        'tokenHash': tokenHash,
        'hint': hint,
        'expiresAt': expiresAt?.toUtc(),
      },
    );
    if (result.isEmpty) return null;
    return ApiToken.fromRow(result.first.toColumnMap());
  }

  @override
  Future<Iterable<ApiToken>> listTokens(String userId) async {
    final result = await _pool.execute(
      _listApiTokens.toSql(),
      parameters: {'userId': userId},
    );
    return result.map((row) => ApiToken.fromRow(row.toColumnMap()));
  }

  @override
  Future<bool> revokeToken({required String userId, required String tokenId}) async {
    final result = await _pool.execute(
      _revokeApiToken.toSql(),
      parameters: {'userId': userId, 'tokenId': tokenId},
    );
    return result.isNotEmpty;
  }

  @override
  Future<DateTime?> claimExport(String userId) async {
    final result = await _pool.execute(_claimApiExport.toSql(), parameters: {'userId': userId});
    final row = result.first.toColumnMap();
    if (row['claimed'] == true) return null;
    return row['last_export_at'] as DateTime;
  }

  @override
  Future<TokenUse?> useToken(Uint8List tokenHash) async {
    final result = await _pool.execute(
      _useApiToken.toSql(),
      parameters: {'tokenHash': tokenHash},
    );
    if (result.isEmpty) return null;
    final row = result.first.toColumnMap();
    return (
      userId: row['user_id'] as String,
      scopes: (row['scopes'] as List).cast<String>(),
      purpose: switch (row['purpose']) {
        final String p => ApiTokenPurpose.fromString(p),
        _ => null,
      },
      minuteStart: row['minute_start'] as DateTime,
      minuteCount: row['minute_count'] as int,
      dayStart: row['day_start'] as DateTime,
      dayCount: row['day_count'] as int,
    );
  }
}
