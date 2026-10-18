import 'misc.dart';

/// What the user made of an [Anomaly].
enum AnomalyStatus {
  /// Not decided yet.
  pending('pending'),

  /// The entry stands and counts as any other.
  valid('valid'),

  /// The entry stays in the log and drops out of every count: records, charts,
  /// volume, goals. For a workout's duration, only its time drops out.
  invalid('invalid');

  final String value;

  new(this.value);

  /// Throws on an unknown word: what the server validates a resolution with.
  factory fromString(String value) {
    return values.firstWhere(
      (status) => status.value == value,
      orElse: () => throw ArgumentError.value(value, 'status', 'unknown anomaly status'),
    );
  }
}

/// The reasons an entry is found suspicious. A word, not an enum: the server
/// may add one, and an older build still reads the anomaly.
abstract final class AnomalyReason {
  /// A finished workout over 6 hours, less its pauses: a timer left running.
  static const durationLeftRunning = 'duration_left_running';

  /// A working set far from the exercise's typical weight.
  static const outlierWeight = 'outlier_weight';

  /// Over 100 reps on a loaded set.
  static const implausibleReps = 'implausible_reps';

  /// Weight and reps that read as each other's.
  static const swapSuspected = 'swap_suspected';
}

/// A suspicious entry in the user's log (heart-api#42): one set, or one
/// workout's duration, found by the server's sweep. Nothing is corrected:
/// [observed] is what was entered, and the user decides ([status]). Editing
/// the entry is the other way out; the next sweep forgets an entry that no
/// longer reads as [observed].
abstract interface class Anomaly implements Model {
  String get id;

  String get workoutId;

  /// When the workout started.
  DateTime? get workoutStart;

  /// The set, for every reason but [AnomalyReason.durationLeftRunning].
  String? get setId;

  String? get exerciseId;

  String? get exerciseName;

  /// One of [AnomalyReason], or a word a newer server added.
  String get reason;

  /// What was entered when it was judged, in stored units: `weight` (kg) and
  /// `reps` for a set, `seconds` for a workout.
  Map<String, dynamic> get observed;

  /// The exercise's median working weight, kg, the set was judged against.
  num? get typical;

  AnomalyStatus get status;

  DateTime get detectedAt;

  DateTime? get resolvedAt;

  factory fromJson(Map json) {
    DateTime? instant(Object? value) => value is String ? DateTime.parse(value) : null;
    return _Anomaly(
      id: json['id'] as String,
      workoutId: json['workoutId'] as String,
      workoutStart: instant(json['workoutStart']),
      setId: json['setId'] as String?,
      exerciseId: json['exerciseId'] as String?,
      exerciseName: json['exerciseName'] as String?,
      reason: json['reason'] as String,
      observed: {...?(json['observed'] as Map?)?.cast<String, dynamic>()},
      typical: json['typical'] as num?,
      status: AnomalyStatus.fromString(json['status'] as String),
      detectedAt: DateTime.parse(json['detectedAt'] as String),
      resolvedAt: instant(json['resolvedAt']),
    );
  }

  /// From a row (snake_case columns; `observed` arrives decoded).
  factory fromRow(Map row) {
    return _Anomaly(
      id: row['id'].toString(),
      workoutId: row['workout_id'].toString(),
      workoutStart: (row['workout_start'] as DateTime?)?.toUtc(),
      setId: row['set_id']?.toString(),
      exerciseId: row['exercise_id']?.toString(),
      exerciseName: row['exercise_name'] as String?,
      reason: row['reason'] as String,
      observed: {...?(row['observed'] as Map?)?.cast<String, dynamic>()},
      typical: row['typical'] as num?,
      status: AnomalyStatus.fromString(row['status'] as String),
      detectedAt: (row['detected_at'] as DateTime).toUtc(),
      resolvedAt: (row['resolved_at'] as DateTime?)?.toUtc(),
    );
  }
}

class _Anomaly implements Anomaly {
  @override
  final String id;
  @override
  final String workoutId;
  @override
  final DateTime? workoutStart;
  @override
  final String? setId;
  @override
  final String? exerciseId;
  @override
  final String? exerciseName;
  @override
  final String reason;
  @override
  final Map<String, dynamic> observed;
  @override
  final num? typical;
  @override
  final AnomalyStatus status;
  @override
  final DateTime detectedAt;
  @override
  final DateTime? resolvedAt;

  const new({
    required this.id,
    required this.workoutId,
    required this.workoutStart,
    required this.setId,
    required this.exerciseId,
    required this.exerciseName,
    required this.reason,
    required this.observed,
    required this.typical,
    required this.status,
    required this.detectedAt,
    required this.resolvedAt,
  });

  @override
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'workoutId': workoutId,
      'workoutStart': ?workoutStart?.toUtc().toIso8601String(),
      'setId': ?setId,
      'exerciseId': ?exerciseId,
      'exerciseName': ?exerciseName,
      'reason': reason,
      'observed': observed,
      'typical': ?typical,
      'status': status.value,
      'detectedAt': detectedAt.toUtc().toIso8601String(),
      'resolvedAt': ?resolvedAt?.toUtc().toIso8601String(),
    };
  }
}
