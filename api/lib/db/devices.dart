part of 'db.dart';

mixin _Devices on _DatabaseBase implements DeviceService {
  @override
  Future<void> registerDevice({
    required String profileId,
    required DevicePlatform platform,
    required String token,
    required String locale,
    required Map<String, dynamic> settings,
  }) async {
    await _pool.execute(
      _upsertDevice.toSql(),
      parameters: {
        'profileId': profileId,
        'platform': platform.value,
        'token': token,
        'locale': locale,
        'settings': jsonEncode(settings),
      },
    );
  }

  @override
  Future<Iterable<DeviceTokenForPush>> tokensWithLocale(String profileId) async {
    final result = await _pool.execute(
      _listDeviceTokensWithLocale.toSql(),
      parameters: {'profileId': profileId},
    );
    return result.map((row) => (token: row[0] as String, locale: row[1] as String));
  }

  @override
  Future<void> deleteToken(String token) async {
    await _pool.execute(
      _deleteDeviceToken.toSql(),
      parameters: {'token': token},
    );
  }
}
