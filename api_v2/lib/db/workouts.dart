part of 'db.dart';

mixin _Workouts on _DatabaseBase implements ApiWorkoutService {
  @override
  Future<WorkoutListResponse> getWorkouts({
    required String userId,
    required String targetUserId,
    required String Function(String) imageUrl,
    String? cursor,
    int? pageSize = 30,
  }) async {
    final rows = await _pool.execute(
      _listWorkouts.toSql(),
      parameters: {'userId': targetUserId, 'cursor': cursor, 'limit': pageSize},
    );
    if (rows.isEmpty) return WorkoutListResponse(workouts: [], cursor: null);
    final workouts = rows.map((row) => WorkoutItem.fromRow(row.toColumnMap(), imageUrl: imageUrl)).toList();
    return WorkoutListResponse(workouts: workouts, cursor: workouts.lastOrNull?.id);
  }

  @override
  Future<WorkoutItem> getWorkout({
    required String userId,
    required String workoutId,
    required String Function(String) imageUrl,
  }) async {
    final rows = await _pool.execute(
      _getWorkout.toSql(),
      parameters: {'workoutId': workoutId, 'userId': userId},
    );
    if (rows.isEmpty) throw NotFound(type: 'Workout', id: workoutId);
    return WorkoutItem.fromRow(rows.first.toColumnMap(), imageUrl: imageUrl);
  }

  @override
  Future<WorkoutItem> createWorkout({
    required String userId,
    required WorkoutRequest body,
    required String Function(String) imageUrl,
  }) async {
    final rows = await _pool.execute(
      _saveWorkout.toSql(),
      parameters: body.toParams(),
    );
    return WorkoutItem.fromRow(rows.first.toColumnMap(), imageUrl: imageUrl);
  }

  @override
  Future<WorkoutItem> updateWorkout({
    required String userId,
    required String workoutId,
    required WorkoutRequest body,
    required String Function(String) imageUrl,
  }) async {
    final rows = await _pool.execute(
      _replaceWorkout.toSql(),
      parameters: {'workoutId': workoutId, ...body.toParams()},
    );
    if (rows.isEmpty) throw NotFound(type: 'Workout', id: workoutId);
    return WorkoutItem.fromRow(rows.first.toColumnMap(), imageUrl: imageUrl);
  }

  @override
  Future<void> deleteWorkout({required String userId, required String workoutId}) async {
    await _pool.execute(
      _deleteWorkout.toSql(),
      parameters: {'workoutId': workoutId, 'userId': userId},
    );
  }
}
