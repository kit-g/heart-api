abstract interface class TimersService {
  /// sets a rest timer on an exercise, in seconds
  /// while also associating it with the current user
  Future<void> setRestTimer({required String exerciseName, required String userId, required int? seconds});

  /// collects all exercise rest times for a given user
  Future<Map<String, int>> getTimers(String userId);
}
