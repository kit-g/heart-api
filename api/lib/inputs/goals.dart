part of 'inputs.dart';

/// `POST /goals` — `{id?, metric, exerciseId?, cadence?, stages: [{target, dueOn?}]}`.
class GoalCreateIn {
  final String? id;
  final GoalMetric metric;
  final String? exerciseId;
  final GoalCadence? cadence;
  final List<GoalStage> stages;

  const new _({
    required this.id,
    required this.metric,
    required this.exerciseId,
    required this.cadence,
    required this.stages,
  });

  static Future<GoalCreateIn> fromRequest(Request req) async {
    final json = await req.json();
    final metric = json.parsed('metric', GoalMetric.fromString);
    final cadence = switch (json['cadence']) {
      null => null,
      _ => json.parsed('cadence', GoalCadence.fromString),
    };
    final input = GoalCreateIn._(
      id: json.uuidV7OrNull(),
      metric: metric,
      exerciseId: json['exerciseId'] as String?,
      cadence: cadence,
      stages: _parseStages(json),
    );
    _validate(metric: metric, exerciseId: input.exerciseId, cadence: cadence, stages: input.stages);
    return input;
  }

  Goal get goal {
    return Goal(id: id, metric: metric, exerciseId: exerciseId, cadence: cadence, stages: stages);
  }
}

/// `PUT /goals/:goalId` — full replace of the definition and its ladder. Stage ids
/// sent back are preserved; stages without one get a fresh id in the db layer.
class GoalUpdateIn {
  final GoalMetric metric;
  final String? exerciseId;
  final GoalCadence? cadence;
  final List<GoalStage> stages;
  final bool archived;

  const new _({
    required this.metric,
    required this.exerciseId,
    required this.cadence,
    required this.stages,
    required this.archived,
  });

  static Future<GoalUpdateIn> fromRequest(Request req) async {
    final json = await req.json();
    final metric = json.parsed('metric', GoalMetric.fromString);
    final cadence = switch (json['cadence']) {
      null => null,
      _ => json.parsed('cadence', GoalCadence.fromString),
    };
    final input = GoalUpdateIn._(
      metric: metric,
      exerciseId: json['exerciseId'] as String?,
      cadence: cadence,
      stages: _parseStages(json),
      archived: json.boolean('archived'),
    );
    _validate(metric: metric, exerciseId: input.exerciseId, cadence: cadence, stages: input.stages);
    return input;
  }

  Goal get goal {
    return Goal(
      metric: metric,
      exerciseId: exerciseId,
      cadence: cadence,
      stages: stages,
      archived: archived,
    );
  }
}

/// `PUT /goals/:goalId/stages/:stageId` — `{achievedAt, achievedBy?}`.
///
/// [achievedBy] is the id of the workout the app credits with the rung. It is
/// optional; when present the db layer checks it is a workout owned by the caller.
class StageAchievedIn {
  final DateTime achievedAt;
  final String? achievedBy;

  const new _({required this.achievedAt, this.achievedBy});

  static Future<StageAchievedIn> fromRequest(Request req) async {
    final json = await req.json();
    return StageAchievedIn._(
      achievedAt: json.timestamp('achievedAt'),
      achievedBy: json.stringOrNull('achievedBy'),
    );
  }
}

List<GoalStage> _parseStages(Map<String, dynamic> json) {
  return [
    for (final stage in json.objects('stages'))
      GoalStage(
        id: stage['id'] as String?,
        target: stage.number('target', exclusiveMin: 0),
        dueOn: stage.dateOrNull('dueOn'),
        // achievedAt and achievedBy both round-trip through the full-replace PUT.
        // Dropping either here re-blanks stamped rungs (achievedAt did exactly that
        // once — "goal needs a restart to show Complete"), so both are read back.
        achievedAt: stage.dateOrNull('achievedAt'),
        achievedBy: stage.stringOrNull('achievedBy'),
      ),
  ];
}

/// The shape rules, mirrored by the CHECK constraints in `2026-07-12.goals.sql`.
void _validate({
  required GoalMetric metric,
  required String? exerciseId,
  required GoalCadence? cadence,
  required List<GoalStage> stages,
}) {
  if (metric.isWholeWorkout && exerciseId != null) {
    throw BadRequest(
      code: 'goal_scope',
      reason: 'the ${metric.value} metric counts whole workouts and takes no exerciseId',
    );
  }
  if (!metric.isWholeWorkout && exerciseId == null) {
    throw BadRequest(
      code: 'goal_scope',
      reason: '${metric.value} is measured per exercise, so exerciseId is required',
    );
  }
  if (cadence != null && stages.length > 1) {
    throw BadRequest(
      code: 'goal_cadence_stages',
      reason: 'a recurring goal has a single standing target, not a ladder of ${stages.length}',
    );
  }
  // Ladder targets are deliberately unconstrained in direction: a descending bench
  // ladder (deload, then rebuild) or a zig-zagging date-ordered plan are real goals,
  // not client bugs. The only per-target rule is target > 0, enforced when parsing.
}
