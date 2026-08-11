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
///
/// [achievedBy] is the id of the workout the app credits with meeting the rung —
/// posterity, and a link the client renders from the goal back to that session.
/// It attributes to the *workout*, not a set, deliberately: no single set achieves
/// a total-volume or total-reps goal (the whole workout, or the week, did), and an
/// `ExerciseSet` id is a client-minted timestamp (`UsesTimestampForId`), so a
/// server-owned goal pointing at one would be a dangling cross-device reference. A
/// workout id is a server-minted UUID, stable everywhere. (Peak metrics —
/// topSetWeight, estimatedOneRepMax, maxConsecutiveReps — could additionally carry
/// a set id later if it earns its keep; not designed for now.) The server stores
/// it opaquely — it does *not* check the workout exists or is owned, because the
/// attributed session is written local-first and may not have synced yet, and a
/// link failing to resolve must never block the achievement. If the id dangles
/// (unsynced, or a workout deleted later) the client renders a stale link;
/// [achievedAt] is the durable fact and never depends on it.
abstract interface class GoalStage implements Model {
  String? get id;

  num get target;

  DateTime? get dueOn;

  DateTime? get achievedAt;

  String? get achievedBy;

  bool get isAchieved;

  factory GoalStage({
    String? id,
    required num target,
    DateTime? dueOn,
    DateTime? achievedAt,
    String? achievedBy,
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
      achievedBy: json['achievedBy'] as String?,
    );
  }

  GoalStage copyWith({String? id, num? target, DateTime? dueOn, DateTime? achievedAt, String? achievedBy});
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
  @override
  final String? achievedBy;

  const _GoalStage({
    this.id,
    required this.target,
    this.dueOn,
    this.achievedAt,
    this.achievedBy,
  });

  @override
  bool get isAchieved => achievedAt != null;

  @override
  GoalStage copyWith({String? id, num? target, DateTime? dueOn, DateTime? achievedAt, String? achievedBy}) {
    return _GoalStage(
      id: id ?? this.id,
      target: target ?? this.target,
      dueOn: dueOn ?? this.dueOn,
      achievedAt: achievedAt ?? this.achievedAt,
      achievedBy: achievedBy ?? this.achievedBy,
    );
  }

  @override
  Map<String, dynamic> toMap() {
    return {
      'id': ?id,
      'target': target,
      'dueOn': ?_date(dueOn),
      'achievedAt': ?achievedAt?.toUtc().toIso8601String(),
      'achievedBy': ?achievedBy,
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

  /// The same goal with its rungs in the order they come due.
  ///
  /// A ladder is a sequence in *time*: the rung you are working toward is the
  /// one that falls next, whatever its number. Ordering by target instead put
  /// "16 km by August" after "12 km by December", which reads backwards.
  ///
  /// Targets are deliberately not constrained. A ladder that descends is a real
  /// intention — strong enough, light enough, and no further — so nothing here
  /// insists they climb.
  ///
  /// A rung with no deadline sorts last: it is the open-ended one, not the
  /// imminent one. Ties keep the order they were given.
  static Goal inDeadlineOrder(Goal goal) {
    if (goal.stages.length < 2) return goal;
    final stages = [...goal.stages]
      ..sort(
        (a, b) => switch ((a.dueOn, b.dueOn)) {
          (final DateTime x, final DateTime y) => x.compareTo(y),
          (null, null) => 0,
          (null, _) => 1,
          (_, null) => -1,
        },
      );
    return goal.copyWith(stages: stages);
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
