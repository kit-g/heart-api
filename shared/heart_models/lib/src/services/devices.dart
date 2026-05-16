enum DevicePlatform {
  ios('ios'),
  android('android'),
  web('web'),
  ;

  final String value;

  const DevicePlatform(this.value);

  factory DevicePlatform.fromString(String v) {
    return switch (v) {
      'ios' => ios,
      'android' => android,
      'web' => web,
      _ => throw ArgumentError('unknown platform: $v'),
    };
  }
}

abstract interface class DeviceService {
  Future<void> registerDevice({
    required String profileId,
    required DevicePlatform platform,
    required String token,
    required Map<String, dynamic> settings,
  });

  Future<Iterable<String>> tokensFor(String profileId);

  Future<void> deleteToken(String token);
}