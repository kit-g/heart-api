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

    final workouts = rows.map(
      (row) {
        return WorkoutItem.fromRow(row.toColumnMap(), imageUrl: imageUrl);
      },
    );

    return WorkoutListResponse(
      workouts: workouts.toList(),
      cursor: workouts.lastOrNull?.id,
    );
  }
}
