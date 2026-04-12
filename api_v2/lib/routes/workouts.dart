import 'package:heart/globals/config.dart';
import 'package:heart/globals/globals.dart';
import 'package:heart/middleware/database.dart';
import 'package:heart/models/connections.dart';
import 'package:heart/models/errors.dart';
import 'package:heart/models/workouts.dart';
import 'package:relic/relic.dart';

const _limitParam = IntQueryParam('pageSize');

Future<bool> _allowed({required ConnectionsService db, required String userId, required String targetUserId}) async {
  if (targetUserId == userId) return true;
  final connections = await db.queryConnections(
    initiatorId: userId,
    targetId: targetUserId,
  );

  return connections?.any((connection) => connection.allows(targetUserId)) ?? false;
}

Future<WorkoutListResponse> getTargetUserWorkouts(final Request request) async {
  final workoutsDb = request.workoutsService;
  final connectionsDb = request.connectionsService;
  final targetUserId = request.pathParameters.raw[#targetUserId]!;
  final pageSize = request.queryParameters(_limitParam);
  final since = request.queryParameters.raw['since'];

  final allowed = await _allowed(db: connectionsDb, userId: request.userId, targetUserId: targetUserId);

  if (!allowed) {
    throw const Forbidden(reason: 'You do not have permission to view these workouts.');
  }

  return workoutsDb.getWorkouts(
    userId: request.userId,
    targetUserId: targetUserId,
    pageSize: pageSize,
    cursor: since,
    imageUrl: request.config.workoutImageUrl,
  );
}
