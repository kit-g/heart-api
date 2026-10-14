import 'misc.dart';

/// The conditions at a moment, as a weather provider or the device's barometer
/// gave them (heart-of-yours#310): metric units, every field optional. Never a
/// location: that is used for the fetch and goes nowhere else.
///
/// Read tolerantly: a field this build doesn't know is kept as it arrived and
/// written back by [toMap].
abstract interface class Weather implements Model {
  /// Degrees Celsius.
  num? get temperature;

  /// Relative humidity, percent.
  num? get humidity;

  /// Hectopascals.
  num? get pressure;

  /// The change in pressure over the past 24 hours, hectopascals.
  num? get pressureTrend;

  bool get isEmpty;

  factory({num? temperature, num? humidity, num? pressure, num? pressureTrend}) {
    return _Weather(temperature, humidity, pressure, pressureTrend, const {});
  }

  factory fromJson(Map json) {
    const known = {'temperature', 'humidity', 'pressure', 'pressureTrend'};
    return _Weather(
      json['temperature'] as num?,
      json['humidity'] as num?,
      json['pressure'] as num?,
      json['pressureTrend'] as num?,
      {
        for (final MapEntry(:key, :value) in json.entries)
          if (!known.contains(key)) '$key': value,
      },
    );
  }
}

class _Weather implements Weather {
  @override
  final num? temperature;
  @override
  final num? humidity;
  @override
  final num? pressure;
  @override
  final num? pressureTrend;

  final Map<String, Object?> _unread;

  const new(this.temperature, this.humidity, this.pressure, this.pressureTrend, this._unread);

  @override
  bool get isEmpty => toMap().isEmpty;

  @override
  Map<String, dynamic> toMap() {
    return {
      ..._unread,
      'temperature': ?temperature,
      'humidity': ?humidity,
      'pressure': ?pressure,
      'pressureTrend': ?pressureTrend,
    };
  }
}

/// A day the user chose not to train: "Not today" (heart-of-yours#312,
/// heart-api#202). One tap, no guilt, no questions.
///
/// What syncs is the moment, an optional reason, the weather, and the session
/// it set aside. The health snapshot the app records beside it (sleep, HRV,
/// resting heart rate, steps) never leaves the device.
///
/// In a program, a skip counts the session as done and moves on, and never
/// moves a base (`docs/2026-10-13.programs.md` in heart-api).
abstract interface class TrainingSkip implements Model {
  String? get id;

  /// When the user decided, by the device's clock.
  DateTime get at;

  /// A one-tap tag, such as `tired`, `sore`, `sick`, `busy` or `just_no`. The
  /// tags are the app's; the server checks only their spelling.
  String? get reason;

  Weather? get weather;

  /// The session set aside, when one was due.
  String? get templateId;

  /// The program that session belongs to.
  String? get programId;

  factory({
    String? id,
    required DateTime at,
    String? reason,
    Weather? weather,
    String? templateId,
    String? programId,
  }) = _TrainingSkip;

  factory fromJson(Map json) {
    return _TrainingSkip(
      id: json['id']?.toString(),
      at: DateTime.parse(json['at'] as String),
      reason: json['reason'] as String?,
      weather: switch (json['weather']) {
        final Map weather => Weather.fromJson(weather),
        _ => null,
      },
      templateId: json['templateId'] as String?,
      programId: json['programId'] as String?,
    );
  }

  factory fromRow(Map row) {
    return _TrainingSkip(
      id: row['id']?.toString(),
      at: switch (row['at']) {
        final DateTime at => at,
        final String at => DateTime.parse(at),
        final other => throw ArgumentError.value(other, 'at'),
      },
      reason: row['reason'] as String?,
      weather: switch (row['weather']) {
        final Map weather => Weather.fromJson(weather),
        _ => null,
      },
      templateId: row['template_id']?.toString(),
      programId: row['program_id']?.toString(),
    );
  }
}

class _TrainingSkip implements TrainingSkip {
  @override
  final String? id;
  @override
  final DateTime at;
  @override
  final String? reason;
  @override
  final Weather? weather;
  @override
  final String? templateId;
  @override
  final String? programId;

  new({this.id, required this.at, this.reason, this.weather, this.templateId, this.programId});

  @override
  Map<String, dynamic> toMap() {
    return {
      'id': ?id,
      'at': at.toUtc().toIso8601String(),
      'reason': ?reason,
      if (weather case final Weather weather when !weather.isEmpty) 'weather': weather.toMap(),
      'templateId': ?templateId,
      'programId': ?programId,
    };
  }
}
