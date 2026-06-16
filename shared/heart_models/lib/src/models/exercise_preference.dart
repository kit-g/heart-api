import 'misc.dart';

/// A per-(user, exercise) measurement-unit preference. The chart-type pref for
/// the same `(user, exercise)` pair lives on the same row but is handled
/// separately (see [ChartPreference]); this model only carries the unit.
abstract interface class ExercisePreference implements Model {
  String get exerciseId;

  MeasurementUnit get unitSystem;

  factory ExercisePreference({
    required String exerciseId,
    required MeasurementUnit unitSystem,
  }) = _ExercisePreference;

  /// Parses the snake_cased `{exercise_id, unit_system}` row/body.
  /// Throws [ArgumentError] (→ 400) on a missing id or an invalid unit.
  factory ExercisePreference.fromRow(Map row) {
    return switch (row) {
      {
        'exercise_id': final String id,
        'unit_system': final String unit,
      }
          when id.isNotEmpty =>
        _ExercisePreference(
          exerciseId: id,
          unitSystem: MeasurementUnit.fromString(unit),
        ),
      _ => throw ArgumentError.value(row, 'row', 'invalid exercise preference'),
    };
  }
}

class _ExercisePreference implements ExercisePreference {
  @override
  final String exerciseId;
  @override
  final MeasurementUnit unitSystem;

  const _ExercisePreference({
    required this.exerciseId,
    required this.unitSystem,
  });

  @override
  Map<String, dynamic> toMap() {
    return {
      'exerciseId': exerciseId,
      'unitSystem': unitSystem.name,
    };
  }
}
