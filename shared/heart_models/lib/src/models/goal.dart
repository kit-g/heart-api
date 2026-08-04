import 'dart:convert';

import 'charts.dart';
import 'misc.dart';

/// What a [Goal] measures. Every value except [workouts] mirrors a
/// [ChartPreferenceType] — same string, same underlying query — so the app routes
/// a goal to the metric query it already has. [workouts] is the frequency metric
/// and is served by `StatsService.getWeeklyWorkoutCount`.
enum GoalMetric {
  workouts('workouts'),
  topSetWeight('topSetWeight'),
  estimatedOneRepMax('estimatedOneRepMax'),
  totalVolume('totalVolume'),
  totalReps('totalReps'),
  maxConsecutiveReps('maxConsecutiveReps'),
  averageWorkingWeight('averageWorkingWeight'),
  assistanceWeight('assistanceWeight'),
  cardioDistance('cardioDistance'),
  cardioDuration('cardioDuration'),
  averagePace('averagePace'),
  totalTimeUnderTension('totalTimeUnderTension'),
  ;

  final String value;

  const GoalMetric(this.value);

  factory GoalMetric.fromString(String v) {
    return switch (v) {
      'workouts' => workouts,
      'topSetWeight' => topSetWeight,
      'estimatedOneRepMax' => estimatedOneRepMax,
      'totalVolume' => totalVolume,
      'totalReps' => totalReps,
      'maxConsecutiveReps' => maxConsecutiveReps,
      'averageWorkingWeight' => averageWorkingWeight,
      'assistanceWeight' => assistanceWeight,
      'cardioDistance' => cardioDistance,
      'cardioDuration' => cardioDuration,
      'averagePace' => averagePace,
      'totalTimeUnderTension' => totalTimeUnderTension,
      _ => throw ArgumentError.value(v, 'metric', 'unknown goal metric'),
    };
  }

  /// [workouts] counts whole workouts, so it carries no exercise. Every other
  /// metric is per-exercise. The DB enforces the same rule (`goals_scope_check`).
  bool get isWholeWorkout => this == workouts;

  /// Pace is the one metric where progress means going *down*, so a ladder of
  /// pace targets descends and a stage is met at `value <= target`.
  bool get lowerIsBetter => this == averagePace;

  /// The chart metric this goal is measured by — `null` only for [workouts],
  /// which has no per-exercise chart.
  ChartPreferenceType? get chart {
    return isWholeWorkout ? null : ChartPreferenceType.fromString(value);
  }
}

/// How often a goal repeats. `null` cadence means a one-off milestone ladder.
enum GoalCadence {
  week('week'),
  month('month'),
  ;

  final String value;

  const GoalCadence(this.value);

  factory GoalCadence.fromString(String v) {
    return switch (v) {
      'week' => week,
      'month' => month,
      _ => throw ArgumentError.value(v, 'cadence', 'unknown cadence'),
    };
  }
}

/// One rung of a goal's ladder: a target, optionally by a date. [achievedAt] is
/// stamped by the app the first time it observes the target being met.
///
/// [id] is minted server-side and is stable across reorders — the stage is
/// addressed by it, never by its position in the array.
abstract interface class GoalStage implements Model {
  String? get id;

  num get target;

  DateTime? get dueOn;

  DateTime? get achievedAt;

  bool get isAchieved;

  factory GoalStage({
    String? id,
    required num target,
    DateTime? dueOn,
    DateTime? achievedAt,
  }) = _GoalStage;

  /// Parses a stage out of the `stages` JSONB array. Keys are camelCase there —
  /// the blob is written and read by us, and travels to the app unchanged.
  factory GoalStage.fromJson(Map json) {
    return _GoalStage(
      id: json['id'] as String?,
      target: switch (json['target']) {
        final num t when t > 0 => t,
        final other => throw ArgumentError.value(other, 'target', 'target must be a positive number'),
      },
      dueOn: switch (json['dueOn']) {
        null => null,
        final String d => DateTime.parse(d),
        final other => throw ArgumentError.value(other, 'dueOn', 'invalid date'),
      },
      achievedAt: switch (json['achievedAt']) {
        null => null,
        final String a => DateTime.parse(a),
        final DateTime a => a,
        final other => throw ArgumentError.value(other, 'achievedAt', 'invalid timestamp'),
      },
    );
  }

  GoalStage copyWith({String? id, num? target, DateTime? dueOn, DateTime? achievedAt});
}

class _GoalStage implements GoalStage {
  @override
  final String? id;
  @override
  final num target;
  @override
  final DateTime? dueOn;
  @override
  final DateTime? achievedAt;

  const _GoalStage({
    this.id,
    required this.target,
    this.dueOn,
    this.achievedAt,
  });

  @override
  bool get isAchieved => achievedAt != null;

  @override
  GoalStage copyWith({String? id, num? target, DateTime? dueOn, DateTime? achievedAt}) {
    return _GoalStage(
      id: id ?? this.id,
      target: target ?? this.target,
      dueOn: dueOn ?? this.dueOn,
      achievedAt: achievedAt ?? this.achievedAt,
    );
  }

  @override
  Map<String, dynamic> toMap() {
    return {
      'id': ?id,
      'target': target,
      'dueOn': ?_date(dueOn),
      'achievedAt': ?achievedAt?.toUtc().toIso8601String(),
    };
  }

  /// `dueOn` is a calendar date, not an instant — a deadline of Christmas is
  /// Christmas wherever the user is standing.
  static String? _date(DateTime? d) {
    if (d == null) return null;
    return '${d.year.toString().padLeft(4, '0')}-'
        '${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}';
  }
}

/// A thing the user is measuring plus a ladder of staged targets.
///
/// Two shapes, told apart by [cadence]:
/// - [cadence] non-null — a recurring goal ("3 workouts a week"). Progress resets
///   each period and it is never "done", so it has exactly one stage.
/// - [cadence] null — a milestone ladder ("two plates by Christmas, three by next
///   Christmas"). Each stage is achieved once, in order.
///
/// Targets are stored canonically metric (kg / km), like every other measurement;
/// the app converts for display.
abstract interface class Goal implements Model {
  String? get id;

  GoalMetric get metric;

  String? get exerciseId;

  GoalCadence? get cadence;

  List<GoalStage> get stages;

  bool get archived;

  DateTime? get createdAt;

  /// A recurring goal is never complete; a ladder is complete when every rung is.
  bool get isComplete;

  /// The rung the user is working toward — the first unachieved stage, or `null`
  /// once the ladder is finished.
  GoalStage? get currentStage;

  factory Goal({
    String? id,
    required GoalMetric metric,
    String? exerciseId,
    GoalCadence? cadence,
    required List<GoalStage> stages,
    bool archived,
    DateTime? createdAt,
  }) = _Goal;

  /// Parses the wire shape (camelCase) — used by the app on `GET /goals`.
  factory Goal.fromJson(Map json) {
    return _Goal(
      id: json['id'] as String?,
      metric: GoalMetric.fromString(json['metric'] as String),
      exerciseId: json['exerciseId'] as String?,
      cadence: switch (json['cadence']) {
        null => null,
        final String c => GoalCadence.fromString(c),
        final other => throw ArgumentError.value(other, 'cadence', 'invalid cadence'),
      },
      stages: _stages(json['stages']),
      archived: switch (json['archived']) {
        1 || true => true,
        _ => false,
      },
      createdAt: switch (json['createdAt']) {
        final String c => DateTime.parse(c),
        _ => null,
      },
    );
  }

  /// Parses a DB row (snake_case columns; `stages` arrives as decoded JSONB).
  factory Goal.fromRow(Map row) {
    return _Goal(
      id: row['id']?.toString(),
      metric: GoalMetric.fromString(row['metric'] as String),
      exerciseId: row['exercise_id']?.toString(),
      cadence: switch (row['cadence']) {
        null => null,
        final String c => GoalCadence.fromString(c),
        final other => throw ArgumentError.value(other, 'cadence', 'invalid cadence'),
      },
      stages: _stages(row['stages']),
      archived: switch (row['archived']) {
        1 || true => true,
        _ => false,
      },
      createdAt: switch (row['created_at']) {
        final DateTime c => c,
        final String c => DateTime.parse(c),
        _ => null,
      },
    );
  }

  static List<GoalStage> _stages(Object? raw) {
    return switch (raw) {
      final String s => _stages(jsonDecode(s)),
      final List l => l.map((each) => GoalStage.fromJson(each as Map)).toList(),
      _ => throw ArgumentError.value(raw, 'stages', 'stages must be a non-empty array'),
    };
  }

  Goal copyWith({
    String? id,
    GoalMetric? metric,
    String? exerciseId,
    GoalCadence? cadence,
    List<GoalStage>? stages,
    bool? archived,
  });
}

class _Goal implements Goal {
  @override
  final String? id;
  @override
  final GoalMetric metric;
  @override
  final String? exerciseId;
  @override
  final GoalCadence? cadence;
  @override
  final List<GoalStage> stages;
  @override
  final bool archived;
  @override
  final DateTime? createdAt;

  const _Goal({
    this.id,
    required this.metric,
    this.exerciseId,
    this.cadence,
    required this.stages,
    this.archived = false,
    this.createdAt,
  });

  @override
  bool get isComplete => cadence == null && stages.every((stage) => stage.isAchieved);

  @override
  GoalStage? get currentStage {
    for (final stage in stages) {
      if (!stage.isAchieved) return stage;
    }
    return null;
  }

  @override
  Goal copyWith({
    String? id,
    GoalMetric? metric,
    String? exerciseId,
    GoalCadence? cadence,
    List<GoalStage>? stages,
    bool? archived,
  }) {
    return _Goal(
      id: id ?? this.id,
      metric: metric ?? this.metric,
      exerciseId: exerciseId ?? this.exerciseId,
      cadence: cadence ?? this.cadence,
      stages: stages ?? this.stages,
      archived: archived ?? this.archived,
      createdAt: createdAt,
    );
  }

  @override
  Map<String, dynamic> toMap() {
    return {
      'id': ?id,
      'metric': metric.value,
      'exerciseId': ?exerciseId,
      'cadence': ?cadence?.value,
      'stages': stages.map((stage) => stage.toMap()).toList(),
      'archived': archived,
      'createdAt': ?createdAt?.toUtc().toIso8601String(),
    };
  }
}
