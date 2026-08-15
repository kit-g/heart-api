import 'misc.dart';

/// A single clearable field on [ExercisePreference]. `column` is the DB column;
/// the enum name is the camelCase wire value used by the `?pref=` query param.
enum ExercisePreferenceField {
  unitSystem('unit_system'),
  restTimer('rest_timer');

  final String column;

  const new(this.column);

  factory fromString(String? v) {
    return switch (v) {
      'unitSystem' => unitSystem,
      'restTimer' => restTimer,
      _ => throw ArgumentError.value(v, 'pref', 'unknown preference field'),
    };
  }
}

/// A per-(user, exercise) preference bundle: the measurement unit and the rest
/// timer (seconds). The chart-type pref for the same `(user, exercise)` row is
/// handled separately (see [ChartPreference]).
abstract interface class ExercisePreference implements Model {
  String get exerciseId;

  MeasurementUnit? get unitSystem;

  int? get restTimer;

  factory({
    required String exerciseId,
    MeasurementUnit? unitSystem,
    int? restTimer,
  }) = _ExercisePreference;

  /// Parses the `{exerciseId, unitSystem?, restTimer?}` request body (camelCase).
  /// At least one pref field must be present. Throws [ArgumentError] (→ 400) on a
  /// missing id, an invalid unit, a non-positive timer, or nothing to update.
  factory fromJson(Map json) {
    final exerciseId = switch (json['exerciseId']) {
      final String id when id.isNotEmpty => id,
      _ => throw ArgumentError.value(json['exerciseId'], 'exerciseId', 'missing exercise id'),
    };
    final unitSystem = switch (json['unitSystem']) {
      null => null,
      final String u => MeasurementUnit.fromString(u),
      final other => throw ArgumentError.value(other, 'unitSystem', 'invalid unit system'),
    };
    final restTimer = switch (json['restTimer']) {
      null => null,
      final int s when s > 0 => s,
      final other => throw ArgumentError.value(other, 'restTimer', 'invalid rest timer'),
    };
    if (unitSystem == null && restTimer == null) {
      throw ArgumentError.value(json, 'json', 'no preference fields to update');
    }
    return _ExercisePreference(exerciseId: exerciseId, unitSystem: unitSystem, restTimer: restTimer);
  }
}

class _ExercisePreference implements ExercisePreference {
  @override
  final String exerciseId;
  @override
  final MeasurementUnit? unitSystem;
  @override
  final int? restTimer;

  const new({
    required this.exerciseId,
    this.unitSystem,
    this.restTimer,
  });

  @override
  Map<String, dynamic> toMap() {
    return {
      'exerciseId': exerciseId,
      'unitSystem': ?unitSystem?.name,
      'restTimer': ?restTimer,
    };
  }
}
