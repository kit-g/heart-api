import 'package:heart/core/request.dart';
import 'package:heart/globals/config.dart';
import 'package:heart/globals/globals.dart';
import 'package:heart/middleware/database.dart';
import 'package:heart/models/errors.dart';
import 'package:heart/models/workouts.dart';
import 'package:heart_models/heart_models.dart';
import 'package:relic/relic.dart';

const _limitParam = IntQueryParam('pageSize');

Future<WorkoutResponse> getTargetUserWorkouts(final Request request) async {
  final targetUserId = request.pathParameters.raw[#targetUserId]!;
  return request.workoutsService.getWorkouts(
    userId: request.userId,
    targetUserId: targetUserId,
    pageSize: request.queryParameters(_limitParam),
    cursor: request.queryParameters.raw['since'],
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