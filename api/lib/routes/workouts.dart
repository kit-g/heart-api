import 'package:heart/core/request.dart';
import 'package:heart/globals/config.dart';
import 'package:heart/globals/globals.dart';
import 'package:heart/inputs/inputs.dart';
import 'package:heart/middleware/database.dart';
import 'package:heart/middleware/s3.dart';
import 'package:heart/models/errors.dart';
import 'package:heart/models/pagination.dart';
import 'package:heart/models/workouts.dart';
import 'package:heart_models/heart_models.dart';
import 'package:relic/relic.dart';

Future<Paginated<Workout>> getTargetUserWorkouts(final Request request) =>
    getTargetUserWorkoutsFor(request, request.rawPathParameters[#targetUserId]!);

Future<Paginated<Workout>> getTargetUserWorkoutsFor(final Request request, final String targetUserId) async {
  final query = PageQuery.fromRequest(request);
  final page = await request.workoutsService.getWorkouts(
    userId: request.userId,
    targetUserId: targetUserId,
    limit: query.limit,
    cursor: query.cursor,
    imageUrl: request.config.cdnAssetUrl,
  );
  return Paginated<Workout>.from(page, itemsKey: 'workouts', cursorOf: (w) => w.id);
}

Future<Workout> getWorkout(final Request request) async {
  final workoutId = request.pathParameters.raw[#workoutId]!;
  return request.workoutsService.getWorkout(
    userId: request.userId,
    workoutId: workoutId,
    imageUrl: request.config.cdnAssetUrl,
  );
}

Future<Workout> getTargetUserWorkout(final Request request) async {
  final targetUserId = request.pathParameters.raw[#targetUserId]!;
  final workoutId = request.pathParameters.raw[#workoutId]!;
  return request.workoutsService.getTargetWorkout(
    requesterId: request.userId,
    targetUserId: targetUserId,
    workoutId: workoutId,
    imageUrl: request.config.cdnAssetUrl,
  );
}

Future<Workout> createWorkout(final Request request) async {
  final body = await request.json();
  final workout = WorkoutRequest(userId: request.userId, body: body);
  return request.workoutsService.createWorkout(
    userId: request.userId,
    body: workout,
    imageUrl: request.config.cdnAssetUrl,
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
    imageUrl: request.config.cdnAssetUrl,
  );
}

Future<Workout> patchWorkout(final Request request) {
  return patchWorkoutById(request, request.rawPathParameters[#workoutId]!);
}

Future<Workout> patchWorkoutById(final Request request, final String workoutId) async {
  final input = await WorkoutPatchIn.fromRequest(request);
  return request.workoutsService.patchWorkout(
    userId: request.userId,
    workoutId: workoutId,
    name: input.name,
    start: input.start,
    end: input.end,
    imageUrl: request.config.cdnAssetUrl,
  );
}

Future<NoContent> deleteWorkout(final Request request) async {
  final workoutId = request.pathParameters.raw[#workoutId]!;
  final userId = request.userId;

  final keys = await request.imageDbService.getWorkoutImageKeys(
    userId: userId,
    workoutId: workoutId,
  );
  for (final key in keys) {
    await request.imageStorageService.deleteObject(key: key);
  }

  await request.workoutsService.deleteWorkout(userId: userId, workoutId: workoutId);
  throw const NoContent();
}
