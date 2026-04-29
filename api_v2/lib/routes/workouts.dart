import 'package:heart/core/request.dart';
import 'package:heart/globals/config.dart';
import 'package:heart/globals/globals.dart';
import 'package:heart/middleware/database.dart';
import 'package:heart/models/errors.dart';
import 'package:heart/models/workouts.dart';
import 'package:heart/routes/permissions.dart';
import 'package:heart_models/heart_models.dart';
import 'package:relic/relic.dart';

const _limitParam = IntQueryParam('pageSize');

Future<WorkoutResponse> getTargetUserWorkouts(final Request request) async {
  final workoutsDb = request.workoutsService;
  final connectionsDb = request.connectionsService;
  final targetUserId = request.pathParameters.raw[#targetUserId]!;
  final pageSize = request.queryParameters(_limitParam);
  final since = request.queryParameters.raw['since'];

  final allowed = await allowedByConnection(db: connectionsDb, userId: request.userId, targetUserId: targetUserId);

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

Future<Workout> getWorkout(final Request request) async {
  final workoutId = request.pathParameters.raw[#workoutId]!;
  return request.workoutsService.getWorkout(
    userId: request.userId,
    workoutId: workoutId,
    imageUrl: request.config.workoutImageUrl,
  );
}

Future<Workout> createWorkout(final Request request) async {
  final body = await request.json();
  final workout = WorkoutRequest(userId: request.userId, body: body);
  return request.workoutsService.createWorkout(
    userId: request.userId,
    body: workout,
    imageUrl: request.config.workoutImageUrl,
  );
}

Future<Workout> updateWorkout(final Request request) async {
  final workoutId = request.pathParameters.raw[#workoutId]!;
  final body = await request.json();
  final workout = WorkoutRequest(userId: request.userId, body: body);
  return request.workoutsService.updateWorkout(
    userId: request.userId,
    workoutId: workoutId,
    body: workout,
    imageUrl: request.config.workoutImageUrl,
  );
}

Future<NoContent> deleteWorkout(final Request request) async {
  final workoutId = request.pathParameters.raw[#workoutId]!;
  await request.workoutsService.deleteWorkout(
    userId: request.userId,
    workoutId: workoutId,
  );
  throw const NoContent();
}