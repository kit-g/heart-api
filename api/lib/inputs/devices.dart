part of 'inputs.dart';

class DeviceRegisterIn {
  final DevicePlatform platform;
  final String token;
  final String locale;
  final Map<String, dynamic> settings;

  /// When a daily push reaches them: the server has no other idea of their time.
  final int? utcOffsetMinutes;

  const new _({
    required this.platform,
    required this.token,
    required this.locale,
    required this.settings,
    this.utcOffsetMinutes,
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
      utcOffsetMinutes: switch (json['utcOffsetMinutes']) {
        null => null,
        final int minutes when minutes >= -720 && minutes <= 840 => minutes,
        _ => throw const BadRequest(reason: 'utcOffsetMinutes must be between -720 and 840'),
      },
    );
  }
}

/// `POST /devices/removals` — `{token}`, the push token this device registered.
class DeviceUnregisterIn {
  final String token;

  const new _(this.token);

  static Future<DeviceUnregisterIn> fromRequest(Request req) async {
    return DeviceUnregisterIn._((await req.json()).string('token', maxLength: 4096));
  }
}
