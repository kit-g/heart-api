part of 'inputs.dart';

/// `POST /skips` — `{id?, at, reason?, weather?, templateId?, programId?}`.
///
/// The health snapshot the app records beside a skip never arrives here:
/// `Request.json()` refuses a body carrying one (`400 health_data`).
class SkipIn {
  static final _reason = RegExp(r'^[a-z][a-z0-9_]{0,31}$');

  /// The fields a weather reading has, each with the range a real one falls in.
  static const _weather = {
    'temperature': (-90, 60),
    'humidity': (0, 100),
    'pressure': (800, 1100),
    'pressureTrend': (-100, 100),
  };

  final TrainingSkip skip;

  const new _(this.skip);

  static Future<SkipIn> fromRequest(Request req) async {
    final json = await req.json();
    return SkipIn._(
      TrainingSkip(
        id: json.uuidV7OrNull(),
        at: json.timestamp('at'),
        reason: switch (json['reason']) {
          null => null,
          final String reason when _reason.hasMatch(reason) => reason,
          _ => throw const BadRequest(code: 'invalid_reason', reason: 'reason must be a snake_case tag of at most 32'),
        },
        weather: switch (json['weather']) {
          null => null,
          final Map weather => _readWeather(weather),
          _ => throw const BadRequest(code: 'invalid_weather', reason: 'weather must be an object'),
        },
        // links, never requirements: anything but a v7 id reads as none
        templateId: switch (json['templateId']) {
          final String id when isUuidV7(id) => id,
          _ => null,
        },
        programId: switch (json['programId']) {
          final String id when isUuidV7(id) => id,
          _ => null,
        },
      ),
    );
  }

  static Weather _readWeather(Map json) {
    for (final MapEntry(:key, :value) in json.entries) {
      final range = _weather[key];
      if (range == null) {
        throw BadRequest(code: 'invalid_weather', reason: 'weather has no field $key');
      }
      if (value is! num || value < range.$1 || value > range.$2) {
        throw BadRequest(
          code: 'invalid_weather',
          reason: 'weather.$key must be a number from ${range.$1} to ${range.$2}',
        );
      }
    }
    return Weather.fromJson(json);
  }
}
