import 'misc.dart';

/// A single clearable field on [ExercisePreference]. `column` is the DB column;
/// the enum name is the camelCase wire value used by the `?pref=` query param.
enum ExercisePreferenceField {
  unitSystem('unit_system'),
  restTimer('rest_timer'),
  note('note');

  final String column;

  new(this.column);

  factory fromString(String? v) {
    return switch (v) {
      'unitSystem' => unitSystem,
      'restTimer' => restTimer,
      'note' => note,
      _ => throw ArgumentError.value(v, 'pref', 'unknown preference field'),
    };
  }
}

/// A per-(user, exercise) preference bundle: the measurement unit, the rest
/// timer (seconds), and the pinned note. The chart-type pref for the same
/// `(user, exercise)` row is handled separately (see [ChartPreference]).
abstract interface class ExercisePreference implements Model {
  static const maxNoteLength = 200;

  String get exerciseId;

  MeasurementUnit? get unitSystem;

  int? get restTimer;

  /// The note pinned to this exercise, applied by the client to each new
  /// instance of it until cancelled. Null when nothing is pinned.
  ///
  /// Distinct from `WorkoutExercise.note`, which records one session and is
  /// allowed more room. The server never copies this into a workout: it cannot
  /// tell a cleared note from an unmentioned one, so a default applied here
  /// would resurrect a note the user deleted.
  String? get note;

  factory({
    required String exerciseId,
    MeasurementUnit? unitSystem,
    int? restTimer,
    String? note,
  }) = _ExercisePreference;

  /// Parses the `{exerciseId, unitSystem?, restTimer?, note?}` request body
  /// (camelCase). At least one pref field must be present. Throws
  /// [ArgumentError] (→ 400) on a missing id, an invalid unit, a non-positive
  /// timer, an over-long note, or nothing to update.
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
    // Blank is nothing pinned, matching how a workout note treats it — but
    // clearing a pin is the DELETE, because the upsert reads null as "leave it".
    final note = switch (json['note']) {
      null => null,
      final String n when n.trim().isEmpty => null,
      final String n when n.trim().length <= maxNoteLength => n.trim(),
      final String _ => throw ArgumentError.value(
        json['note'],
        'note',
        'a pinned note is at most $maxNoteLength characters',
      ),
      final other => throw ArgumentError.value(other, 'note', 'a pinned note must be a string'),
    };
    if (unitSystem == null && restTimer == null && note == null) {
      throw ArgumentError.value(json, 'json', 'no preference fields to update');
    }
    return _ExercisePreference(
      exerciseId: exerciseId,
      unitSystem: unitSystem,
      restTimer: restTimer,
      note: note,
    );
  }
}

class _ExercisePreference implements ExercisePreference {
  @override
  final String exerciseId;
  @override
  final MeasurementUnit? unitSystem;
  @override
  final int? restTimer;
  @override
  final String? note;

  const new({
    required this.exerciseId,
    this.unitSystem,
    this.restTimer,
    this.note,
  });

  @override
  Map<String, dynamic> toMap() {
    return {
      'exerciseId': exerciseId,
      'unitSystem': ?unitSystem?.name,
      'restTimer': ?restTimer,
      'note': ?note,
    };
  }
}
