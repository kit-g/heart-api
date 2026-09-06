part of 'db.dart';

mixin _Goals on _DatabaseBase implements IdempotentGoalService {
  @override
  Future<Iterable<Goal>> getTargetUserGoals({
    required String requesterId,
    required String targetUserId,
    bool archived = false,
  }) async {
    final rows = await _pool.execute(
      _listTargetGoals.toSql(),
      parameters: {'requesterId': requesterId, 'targetUserId': targetUserId, 'archived': archived},
    );
    if (rows.isNotEmpty && rows.first.toColumnMap()['forbidden'] == true) {
      throw const Forbidden(reason: 'You do not have permission to view these goals.');
    }
    return rows.map((row) => Goal.fromRow(row.toColumnMap()));
  }

  @override
  Future<Goal> createGoal(Goal goal, String userId) async => (await createGoalOrExisting(goal, userId)).$1;

  @override
  Future<(Goal, bool created)> createGoalOrExisting(Goal goal, String userId) async {
    try {
      final result = await _retryOnCreateRace(
        () => _pool.execute(
          _createGoal.toSql(),
          parameters: {
            'id': goal.id,
            'userId': userId,
            'metric': goal.metric.value,
            'exerciseId': goal.exerciseId,
            'cadence': goal.cadence?.value,
            'stages': _encodeStages(goal.stages),
          },
        ),
      );
      // The id pre-check (kit-g/heart-api#66) has already ruled out "this id
      // is mine", so an empty result here can only be the cap guard firing —
      // an id belonging to someone else trips the pkey exception instead.
      if (result.isEmpty) {
        throw const BadRequest(
          code: 'goal_limit',
          reason: 'you can have at most $_maxActiveGoals active goals; archive or delete one first',
        );
      }
      final row = result.first.toColumnMap();
      return (Goal.fromRow(row), row['created'] as bool);
    } on ServerException catch (e) {
      _rethrowForeignId(e);
    }
  }

  @override
  Future<Goal> updateGoal(String goalId, Goal goal, String userId) async {
    final result = await _pool.execute(
      _updateGoal.toSql(),
      parameters: {
        'id': goalId,
        'userId': userId,
        'metric': goal.metric.value,
        'exerciseId': goal.exerciseId,
        'cadence': goal.cadence?.value,
        'stages': _encodeStages(goal.stages),
        'archived': goal.archived,
      },
    );
    if (result.isEmpty) throw NotFound(type: 'Goal', id: goalId, code: 'goal_not_found');
    return Goal.fromRow(result.first.toColumnMap());
  }

  @override
  Future<void> deleteGoal(String goalId, String userId) async {
    await _pool.execute(
      _deleteGoal.toSql(),
      parameters: {'id': goalId, 'userId': userId},
    );
  }

  @override
  Future<Goal> markStageAchieved(
    String goalId,
    String stageId,
    String userId,
    DateTime achievedAt, {
    String? achievedBy,
  }) async {
    // achievedBy is stored opaquely, not validated against the workouts table:
    // the attributed workout may not have synced to the server yet (workouts are
    // written local-first and their ids minted server-side), and a link failing
    // to resolve must never block the achievement — achievedAt is the durable
    // fact, achievedBy is enrichment that degrades to a stale link if it dangles.
    final result = await _pool.execute(
      _markStageAchieved.toSql(),
      parameters: {
        'goalId': goalId,
        'stageId': stageId,
        'userId': userId,
        'achievedAt': achievedAt.toUtc().toIso8601String(),
        'achievedBy': achievedBy,
      },
    );
    if (result.isEmpty) throw NotFound(type: 'Goal stage', id: stageId, code: 'goal_stage_not_found');
    return Goal.fromRow(result.first.toColumnMap());
  }

  /// Stage ids are minted here, not by the client: they are what
  /// `PUT /goals/:goalId/stages/:stageId` addresses, and they must survive a
  /// reordered ladder. An incoming stage that already has one keeps it.
  String _encodeStages(List<GoalStage> stages) {
    return jsonEncode([
      for (final stage in stages) stage.copyWith(id: stage.id ?? uuidV7()).toMap(),
    ]);
  }
}
