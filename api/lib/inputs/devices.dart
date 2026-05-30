part of 'inputs.dart';

class DeviceRegisterIn {
  final DevicePlatform platform;
  final String token;
  final String locale;
  final Map<String, dynamic> settings;

  const DeviceRegisterIn._({
    required this.platform,
    required this.token,
    required this.locale,
    required this.settings,
  });

  static Future<DeviceRegisterIn> fromRequest(Request req) async {
    final json = await req.json();
    return DeviceRegisterIn._(
      platform: json.parsed('platform', DevicePlatform.fromString),
      token: json.string('token'),
      locale: req.locale(
        req.config.supportedLocales,
        req.config.defaultLocale,
      ),
      settings: json.mapping('settings'),
    );
  }
}
