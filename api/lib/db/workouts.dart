part of 'db.dart';

mixin _Workouts on _DatabaseBase implements ApiWorkoutService {
  @override
  Future<Page<Workout>> getWorkouts({
    required String userId,
    required String targetUserId,
    required String Function(String) imageUrl,
    String? cursor,
    int limit = 30,
  }) async {
    // Fetch one extra row so hasMore is authoritative without a second query.
    final rows = await _pool.execute(
      _listWorkouts.toSql(),
      parameters: {'requesterId': userId, 'targetUserId': targetUserId, 'cursor': cursor, 'limit': limit + 1},
    );
    if (rows.isNotEmpty && rows.first.toColumnMap()['forbidden'] == true) {
      throw const Forbidden(reason: 'You do not have permission to view these workouts.');
    }
    final workouts = rows.map((row) => Workout.fromRow(row.toColumnMap(), imageUrl: imageUrl)).toList();
    final hasMore = workouts.length > limit;
    return Page(items: hasMore ? workouts.sublist(0, limit) : workouts, hasMore: hasMore);
  }

  @override
  Future<Workout> getWorkout({
    required String userId,
    required String workoutId,
    required String Function(String) imageUrl,
  }) async {
    final rows = await _pool.execute(
      _getWorkout.toSql(),
      parameters: {'workoutId': workoutId, 'userId': userId},
    );
    if (rows.isEmpty) throw NotFound(type: 'Workout', id: workoutId);
    return Workout.fromRow(rows.first.toColumnMap(), imageUrl: imageUrl);
  }

  @override
  Future<Workout> getTargetWorkout({
    required String requesterId,
    required String targetUserId,
    required String workoutId,
    required String Function(String) imageUrl,
  }) async {
    final rows = await _pool.execute(
      _getTargetWorkout.toSql(),
      parameters: {'requesterId': requesterId, 'targetUserId': targetUserId, 'workoutId': workoutId},
    );
    if (rows.isNotEmpty && rows.first.toColumnMap()['forbidden'] == true) {
      throw const Forbidden(reason: 'You do not have permission to view this workout.');
    }
    if (rows.isEmpty) throw NotFound(type: 'Workout', id: workoutId);
    return Workout.fromRow(rows.first.toColumnMap(), imageUrl: imageUrl);
  }

  @override
  Future<Workout> createWorkout({
    required String userId,
    required WorkoutRequest body,
    required String Function(String) imageUrl,
  }) async {
    final rows = await _pool.execute(
      _saveWorkout.toSql(),
      parameters: body.toParams(),
    );
    return Workout.fromRow(rows.first.toColumnMap(), imageUrl: imageUrl);
  }

  @override
  Future<Workout> updateWorkout({
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
    return Workout.fromRow(rows.first.toColumnMap(), imageUrl: imageUrl);
  }

  @override
  Future<Workout> patchWorkout({
    required String userId,
    required String workoutId,
    required String Function(String) imageUrl,
    String? name,
    DateTime? start,
    DateTime? end,
  }) async {
    final rows = await _pool.execute(
      _patchWorkout.toSql(),
      parameters: {
        'workoutId': workoutId,
        'userId': userId,
        'name': name,
        'startedAt': start,
        'completedAt': end,
      },
    );
    if (rows.isEmpty) throw NotFound(type: 'Workout', id: workoutId);
    return Workout.fromRow(rows.first.toColumnMap(), imageUrl: imageUrl);
  }

  @override
  Future<void> deleteWorkout({required String userId, required String workoutId}) async {
    await _pool.execute(
      _deleteWorkout.toSql(),
      parameters: {'workoutId': workoutId, 'userId': userId},
    );
  }
}
