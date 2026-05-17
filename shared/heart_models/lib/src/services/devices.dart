enum DevicePlatform {
  ios('ios'),
  android('android'),
  web('web'),
  ;

  final String value;

  const DevicePlatform(this.value);

  factory DevicePlatform.fromString(String v) {
    return switch (v.toLowerCase()) {
      'ios' => ios,
      'android' => android,
      'web' => web,
      _ => throw ArgumentError('unknown platform: $v'),
    };
  }
}

/// One registered device token + the locale to render notification copy in.
typedef DeviceToken = ({String token, String locale});

abstract interface class DeviceService {
  Future<void> registerDevice({
    required String profileId,
    required DevicePlatform platform,
    required String token,
    required String locale,
    required Map<String, dynamic> settings,
  });

  /// All FCM tokens registered for [profileId], each paired with the locale
  /// that device asked for (BCP-47 underscore form, e.g. `en_CA`).
  /// Used by the API events consumer to render per-locale push copy.
  Future<Iterable<DeviceToken>> tokensWithLocale(String profileId);

  Future<void> deleteToken(String token);
}
