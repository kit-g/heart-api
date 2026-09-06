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

  /// `created` is true when this call minted the row; false when [goal].id
  /// already named a goal the caller owns — the upsync replay's
  /// idempotent-retry case (kit-g/heart-api#66) — in which case the existing
  /// goal comes back untouched and the retry never counts against the active
  /// goal cap. Goals carry no natural key, so an id is the only thing a
  /// retry can match on.
  Future<(Goal, bool created)> createGoal(Goal goal, String userId);

  Future<Goal> updateGoal(String goalId, Goal goal, String userId);

  Future<void> deleteGoal(String goalId, String userId);

  /// Stamps a single stage as achieved, leaving the rest of the ladder intact.
  /// Idempotent — re-sending overwrites the timestamp rather than failing.
  ///
  /// [achievedBy], when given, credits the workout that met the rung (a link the
  /// client renders). Stored as-sent — not validated against the workouts table,
  /// so it survives a session that hasn't synced to the server yet; a dangling id
  /// just renders as a stale link and never blocks the achievement.
  Future<Goal> markStageAchieved(
    String goalId,
    String stageId,
    String userId,
    DateTime achievedAt, {
    String? achievedBy,
  });
}
