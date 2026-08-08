import '../models/goal.dart';

abstract interface class GoalService {
  /// Goals a user has, visible to the owner and to their active connections —
  /// the same read model as workouts. [requesterId] must be [targetUserId] or an
  /// active COACH/PEER of them, or this throws `Forbidden`. Writing stays
  /// owner-only. Archived goals are excluded.
  Future<Iterable<Goal>> getTargetUserGoals({required String requesterId, required String targetUserId});

  Future<Goal> createGoal(Goal goal, String userId);

  Future<Goal> updateGoal(String goalId, Goal goal, String userId);

  Future<void> deleteGoal(String goalId, String userId);

  /// Stamps a single stage as achieved, leaving the rest of the ladder intact.
  /// Idempotent — re-sending overwrites the timestamp rather than failing.
  Future<Goal> markStageAchieved(String goalId, String stageId, String userId, DateTime achievedAt);
}
