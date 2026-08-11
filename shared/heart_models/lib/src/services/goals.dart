import '../models/goal.dart';

abstract interface class GoalService {
  /// Goals a user has, visible to the owner and to their active connections —
  /// the same read model as workouts. [requesterId] must be [targetUserId] or an
  /// active COACH/PEER of them, or this throws `Forbidden`. Writing stays
  /// owner-only.
  ///
  /// [archived] selects which slice, never a union: the default `false` returns
  /// the live goals (those counting against the cap), `true` returns *only* the
  /// archived ones — the "achieved" surface behind a completed goal's card.
  Future<Iterable<Goal>> getTargetUserGoals({
    required String requesterId,
    required String targetUserId,
    bool archived = false,
  });

  Future<Goal> createGoal(Goal goal, String userId);

  Future<Goal> updateGoal(String goalId, Goal goal, String userId);

  Future<void> deleteGoal(String goalId, String userId);

  /// Stamps a single stage as achieved, leaving the rest of the ladder intact.
  /// Idempotent — re-sending overwrites the timestamp rather than failing.
  ///
  /// [achievedBy], when given, credits the workout that met the rung (a link the
  /// client renders). It must be a workout owned by [userId], else `BadRequest`.
  Future<Goal> markStageAchieved(
    String goalId,
    String stageId,
    String userId,
    DateTime achievedAt, {
    String? achievedBy,
  });
}
