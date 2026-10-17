import 'misc.dart';

/// Global, per-user preferences (the unit-system default, theme mode, accent
/// color, and any future UI toggles). Known fields are typed; unknown keys are
/// preserved in [extra] so the app can add toggles without a backend change.
///
/// Parsing is lenient — an unrecognized `unitSystem` value degrades to `null`
/// rather than throwing, so a malformed blob never 500s the account upsert.
class Settings implements Model {
  final MeasurementUnit? unitSystem;
  final String? themeMode;
  final String? accentColor;

  /// The day the user's week starts on, ISO: 1 Monday to 7 Sunday. Null until
  /// the app reports it.
  final int? firstWeekday;

  final Map<String, dynamic> extra;

  const new({
    this.unitSystem,
    this.themeMode,
    this.accentColor,
    this.firstWeekday,
    this.extra = const {},
  });

  static const _known = {'unitSystem', 'unit_system', 'themeMode', 'accentColor', 'firstWeekday'};

  factory fromJson(Map? json) {
    if (json == null) return const Settings();
    return Settings(
      unitSystem: switch (json['unitSystem'] ?? json['unit_system']) {
        'imperial' => MeasurementUnit.imperial,
        'metric' => MeasurementUnit.metric,
        _ => null,
      },
      themeMode: json['themeMode'] as String?,
      accentColor: json['accentColor'] as String?,
      firstWeekday: switch (json['firstWeekday']) {
        final int day when day >= 1 && day <= 7 => day,
        _ => null,
      },
      extra: {
        for (final entry in json.entries)
          if (!_known.contains(entry.key)) entry.key as String: entry.value,
      },
    );
  }

  @override
  Map<String, dynamic> toMap() {
    return {
      ...extra,
      'unitSystem': ?unitSystem?.name,
      'themeMode': ?themeMode,
      'accentColor': ?accentColor,
      'firstWeekday': ?firstWeekday,
    };
  }

  Settings copyWith({
    MeasurementUnit? unitSystem,
    String? themeMode,
    String? accentColor,
    int? firstWeekday,
    Map<String, dynamic>? extra,
  }) {
    return Settings(
      unitSystem: unitSystem ?? this.unitSystem,
      themeMode: themeMode ?? this.themeMode,
      accentColor: accentColor ?? this.accentColor,
      firstWeekday: firstWeekday ?? this.firstWeekday,
      extra: extra ?? this.extra,
    );
  }
}
