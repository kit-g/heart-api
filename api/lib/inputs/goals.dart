part of 'inputs.dart';

/// `POST /goals` — `{metric, exerciseId?, cadence?, stages: [{target, dueOn?}]}`.
class GoalCreateIn {
  final GoalMetric metric;
  final String? exerciseId;
  final GoalCadence? cadence;
  final List<GoalStage> stages;

  const GoalCreateIn._({
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
      metric: metric,
      exerciseId: json['exerciseId'] as String?,
      cadence: cadence,
      stages: _parseStages(json),
    );
    _validate(metric: metric, exerciseId: input.exerciseId, cadence: cadence, stages: input.stages);
    return input;
  }

  Goal get goal {
    return Goal(metric: metric, exerciseId: exerciseId, cadence: cadence, stages: stages);
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

  const GoalUpdateIn._({
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

/// `PUT /goals/:goalId/stages/:stageId` — `{achievedAt}`.
class StageAchievedIn {
  final DateTime achievedAt;

  const StageAchievedIn._({required this.achievedAt});

  static Future<StageAchievedIn> fromRequest(Request req) async {
    final json = await req.json();
    return StageAchievedIn._(achievedAt: json.timestamp('achievedAt'));
  }
}

List<GoalStage> _parseStages(Map<String, dynamic> json) {
  return [
    for (final stage in json.objects('stages'))
      GoalStage(
        id: stage['id'] as String?,
        target: stage.number('target', exclusiveMin: 0),
        dueOn: stage.dateOrNull('dueOn'),
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
    throw BadRequest(reason: 'the ${metric.value} metric counts whole workouts and takes no exerciseId');
  }
  if (!metric.isWholeWorkout && exerciseId == null) {
    throw BadRequest(reason: '${metric.value} is measured per exercise, so exerciseId is required');
  }
  if (cadence != null && stages.length > 1) {
    throw BadRequest(reason: 'a recurring goal has a single standing target, not a ladder of ${stages.length}');
  }
  _assertLadderClimbs(metric, stages);
}

/// A ladder that goes backwards is a client bug, not a goal. Pace is the one metric
/// where progress means going down, so its ladder descends.
void _assertLadderClimbs(GoalMetric metric, List<GoalStage> stages) {
  for (var i = 1; i < stages.length; i++) {
    final (previous, current) = (stages[i - 1].target, stages[i].target);
    final climbs = metric.lowerIsBetter ? current < previous : current > previous;
    if (!climbs) {
      final direction = metric.lowerIsBetter ? 'decrease' : 'increase';
      throw BadRequest(reason: 'stage targets must $direction along the ladder: $previous then $current');
    }
  }
}
