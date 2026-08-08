part of 'db.dart';

mixin _Goals on _DatabaseBase implements GoalService {
  @override
  Future<Iterable<Goal>> getTargetUserGoals({required String requesterId, required String targetUserId}) async {
    final rows = await _pool.execute(
      _listTargetGoals.toSql(),
      parameters: {'requesterId': requesterId, 'targetUserId': targetUserId},
    );
    if (rows.isNotEmpty && rows.first.toColumnMap()['forbidden'] == true) {
      throw const Forbidden(reason: 'You do not have permission to view these goals.');
    }
    return rows.map((row) => Goal.fromRow(row.toColumnMap()));
  }

  @override
  Future<Goal> createGoal(Goal goal, String userId) async {
    final result = await _pool.execute(
      _createGoal.toSql(),
      parameters: {
        'userId': userId,
        'metric': goal.metric.value,
        'exerciseId': goal.exerciseId,
        'cadence': goal.cadence?.value,
        'stages': _encodeStages(goal.stages),
      },
    );
    // No row means the insert's cap guard fired — the user is already at the limit.
    if (result.isEmpty) {
      throw const BadRequest(
        code: 'goal_limit',
        reason: 'you can have at most $_maxActiveGoals active goals; archive or delete one first',
      );
    }
    return Goal.fromRow(result.first.toColumnMap());
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
  Future<Goal> markStageAchieved(String goalId, String stageId, String userId, DateTime achievedAt) async {
    final result = await _pool.execute(
      _markStageAchieved.toSql(),
      parameters: {
        'goalId': goalId,
        'stageId': stageId,
        'userId': userId,
        'achievedAt': achievedAt.toUtc().toIso8601String(),
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
