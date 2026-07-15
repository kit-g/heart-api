import '../models/goal.dart';

abstract interface class GoalService {
  Future<Iterable<Goal>> getGoals(String userId);

  Future<Goal> createGoal(Goal goal, String userId);

  Future<Goal> updateGoal(String goalId, Goal goal, String userId);

  Future<void> deleteGoal(String goalId, String userId);

  /// Stamps a single stage as achieved, leaving the rest of the ladder intact.
  /// Idempotent — re-sending overwrites the timestamp rather than failing.
  Future<Goal> markStageAchieved(String goalId, String stageId, String userId, DateTime achievedAt);
}
