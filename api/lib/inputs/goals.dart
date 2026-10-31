part of 'inputs.dart';

/// `POST /goals` — `{id?, metric, exerciseId?, pattern?, muscle?, cadence?, stages: [{target, dueOn?}]}`.
class GoalCreateIn {
  final String? id;
  final GoalMetric metric;
  final String? exerciseId;
  final String? pattern;
  final String? muscle;
  final GoalCadence? cadence;
  final List<GoalStage> stages;

  const new _({
    required this.id,
    required this.metric,
    required this.exerciseId,
    required this.pattern,
    required this.muscle,
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
      pattern: json.subjectKey('pattern'),
      muscle: json.subjectKey('muscle'),
      cadence: cadence,
      stages: _parseStages(json),
    );
    _validate(
      metric: metric,
      exerciseId: input.exerciseId,
      pattern: input.pattern,
      muscle: input.muscle,
      cadence: cadence,
      stages: input.stages,
    );
    return input;
  }

  Goal get goal {
    return Goal(
      id: id,
      metric: metric,
      exerciseId: exerciseId,
      pattern: pattern,
      muscle: muscle,
      cadence: cadence,
      stages: stages,
    );
  }
}

/// `PUT /goals/:goalId` — full replace of the definition and its ladder. Stage ids
/// sent back are preserved; stages without one get a fresh id in the db layer.
class GoalUpdateIn {
  final GoalMetric metric;
  final String? exerciseId;
  final String? pattern;
  final String? muscle;
  final GoalCadence? cadence;
  final List<GoalStage> stages;
  final bool archived;

  const new _({
    required this.metric,
    required this.exerciseId,
    required this.pattern,
    required this.muscle,
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
      pattern: json.subjectKey('pattern'),
      muscle: json.subjectKey('muscle'),
      cadence: cadence,
      stages: _parseStages(json),
      archived: json.boolean('archived'),
    );
    _validate(
      metric: metric,
      exerciseId: input.exerciseId,
      pattern: input.pattern,
      muscle: input.muscle,
      cadence: cadence,
      stages: input.stages,
    );
    return input;
  }

  Goal get goal {
    return Goal(
      metric: metric,
      exerciseId: exerciseId,
      pattern: pattern,
      muscle: muscle,
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

extension on Map<String, dynamic> {
  /// A pattern or muscle key: a snake_case content identifier. Which keys exist
  /// is the library's business, and it can add one without a release, so the
  /// spelling is all that is checked.
  String? subjectKey(String field) {
    return switch (this[field]) {
      null => null,
      final String key when _contentKey.hasMatch(key) => key,
      _ => throw BadRequest(
        code: 'invalid_subject',
        reason: '$field must be a snake_case key of at most 64 characters',
      ),
    };
  }
}

/// The shape rules, mirrored by the CHECK constraints on `goals`.
void _validate({
  required GoalMetric metric,
  required String? exerciseId,
  required String? pattern,
  required String? muscle,
  required GoalCadence? cadence,
  required List<GoalStage> stages,
}) {
  final subjects = [exerciseId, pattern, muscle].nonNulls.length;
  if (metric.isWholeWorkout && subjects > 0) {
    throw BadRequest(
      code: 'goal_scope',
      reason: 'the ${metric.value} metric counts whole workouts and takes no exerciseId, pattern or muscle',
    );
  }
  if (metric.countsSubject && subjects != 1) {
    throw BadRequest(
      code: 'goal_scope',
      reason: '${metric.value} counts one subject, so exactly one of exerciseId, pattern and muscle is required',
    );
  }
  if (!metric.isWholeWorkout && !metric.countsSubject && (exerciseId == null || subjects > 1)) {
    throw BadRequest(
      code: 'goal_scope',
      reason: '${metric.value} is measured per exercise, so exerciseId is required and pattern and muscle are not',
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

/// `GET …/goals?archived=` — active goals unless `archived=true`.
class GoalsQuery {
  final bool archived;

  const new _({required this.archived});

  static GoalsQuery fromRequest(Request req) => read(Query.of(req));

  static GoalsQuery read(Query q) => GoalsQuery._(archived: q.boolean('archived'));
}
