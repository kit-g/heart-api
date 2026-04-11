import 'package:heart/globals/config.dart';
import 'package:heart/globals/globals.dart';
import 'package:heart/middleware/database.dart';
import 'package:heart/models/workouts.dart';
import 'package:relic/relic.dart';

const _limitParam = IntQueryParam('pageSize');

Future<WorkoutListResponse> getTargetUserWorkouts(final Request request) async {
  final db = request.workoutsService;
  final targetUserId = request.pathParameters.raw[#targetUserId]!;
  final pageSize = request.queryParameters(_limitParam);
  final since = request.queryParameters.raw['since'];

  return db.getWorkouts(
    userId: request.userId,
    targetUserId: targetUserId,
    pageSize: pageSize,
    cursor: since,
    imageUrl: request.config.workoutImageUrl,
  );
}
