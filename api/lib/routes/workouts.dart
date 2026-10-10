import 'dart:convert';

import 'package:heart/core/handler.dart';
import 'package:heart/core/request.dart';
import 'package:heart/globals/config.dart';
import 'package:heart/globals/globals.dart';
import 'package:heart/inputs/inputs.dart';
import 'package:heart/middleware/aws.dart';
import 'package:heart/middleware/database.dart';
import 'package:heart/middleware/s3.dart';
import 'package:heart/models/errors.dart';
import 'package:heart/models/imports.dart';
import 'package:heart/models/pagination.dart';
import 'package:heart/models/workouts.dart';
import 'package:heart_aws/heart_aws.dart';
import 'package:heart_models/heart_models.dart';
import 'package:logging/logging.dart' as logging;
import 'package:relic/relic.dart';

final _logger = logging.Logger('Workouts');

Future<Paginated<Workout>> getTargetUserWorkouts(Request request) =>
    getTargetUserWorkoutsFor(request, request.rawPathParameters[#targetUserId]!);

Future<Paginated<Workout>> getTargetUserWorkoutsFor(Request request, String targetUserId) async {
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

Future<Workout> getWorkout(Request request) async {
  final workoutId = request.pathParameters.raw[#workoutId]!;
  return request.workoutsService.getWorkout(
    userId: request.userId,
    workoutId: workoutId,
    imageUrl: request.config.cdnAssetUrl,
  );
}

Future<Workout> getTargetUserWorkout(Request request) async {
  final targetUserId = request.pathParameters.raw[#targetUserId]!;
  final workoutId = request.pathParameters.raw[#workoutId]!;
  return request.workoutsService.getTargetWorkout(
    requesterId: request.userId,
    targetUserId: targetUserId,
    workoutId: workoutId,
    imageUrl: request.config.cdnAssetUrl,
  );
}

Future<Model> createWorkout(Request request) async {
  final body = await request.json();
  final (workout, isNew) = await request.workoutsService.createWorkout(
    userId: request.userId,
    body: WorkoutRequest(userId: request.userId, body: body),
    imageUrl: request.config.cdnAssetUrl,
  );
  if (isNew) return Created(workout);
  return workout;
}

/// Bulk import of another app's CSV export; responds with a report of what
/// was created, skipped (already imported or declined), and which exercises
/// were created as the user's customs. With `dryRun=true`, writes nothing and
/// responds with the preview instead — the input for the consent step.
///
/// A file in a known layout whose rows the parser can't read is not refused:
/// it is kept for a person to import by hand, answered `202` with a note
/// saying so, and the owner is alerted. A switcher's whole history is worth a
/// manual pass; a 400 would send them away with it. An import that skipped
/// rows is kept too, quietly, for whoever wants to see what the parser
/// refused.
Future<Model> importWorkouts(Request request) async {
  final input = await ImportWorkoutsIn.fromRequest(request);
  return switch (input.batch) {
    final WorkoutImport batch => _importBatch(request, input, batch),
    null => _parkExport(request, input),
  };
}

Future<Model> _importBatch(Request request, ImportWorkoutsIn input, WorkoutImport batch) async {
  if (input.dryRun) {
    return request.workoutsService.previewImport(userId: request.userId, batch: batch);
  }
  final report = await request.workoutsService.importWorkouts(
    userId: request.userId,
    batch: batch,
    createCustom: input.createCustom,
  );
  if (batch.rowsSkipped > 0) await _keepPartial(request, input);
  if (report.workoutsCreated >= 500 || report.setsCreated >= 5000) {
    // a big import is legitimate exactly once per user per source app —
    // worth a human glance either way
    await _alertOwner(
      request,
      subject: 'Large workout import',
      message:
          'User ${request.userId} just imported ${report.workoutsCreated} workouts '
          '(${report.setsCreated} sets) from ${report.source}.',
    );
  }
  return report;
}

Future<Model> _parkExport(Request request, ImportWorkoutsIn input) async {
  final (:key, :already) = await request.importStorage.keep(
    userId: request.userId,
    source: input.source,
    bytes: utf8.encode(input.csv),
    as: .parked,
  );
  // the same file sent again (a retry, a dry run then a commit) is one object
  // and one alert
  if (!already) {
    await _alertOwner(
      request,
      subject: 'Parked workout import',
      message:
          'User ${request.userId} sent a ${input.source.label} export the parser could not read '
          '(${input.unreadable}). It is at $key, waiting for a manual import.',
    );
  }
  return Accepted(WorkoutImportParked(source: input.source, key: key, reason: input.unreadable!));
}

/// Keeps an export the parser read only in part, best-effort: the import has
/// already happened, and a failure here is a lost sample, not a lost import.
Future<void> _keepPartial(Request request, ImportWorkoutsIn input) async {
  try {
    await request.importStorage.keep(
      userId: request.userId,
      source: input.source,
      bytes: utf8.encode(input.csv),
      as: .partial,
    );
  } catch (e, st) {
    _logger.warning('failed to keep a partially read ${input.source.label} export', e, st);
  }
}

/// Tells the owner, best-effort: an alert must never fail the request it is
/// about.
Future<void> _alertOwner(Request request, {required String subject, required String message}) async {
  try {
    final sns = Sns(
      credentialsProvider: request.awsConfig.credentialsProvider,
      region: request.awsConfig.region,
    );
    await sns.publish(topicArn: request.config.monitoringTopicArn, subject: subject, message: message);
  } catch (e, st) {
    _logger.warning('failed to publish the alert "$subject"', e, st);
  }
}

Future<Workout> updateWorkout(Request request) async {
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

Future<Workout> patchWorkout(Request request) {
  return patchWorkoutById(request, request.rawPathParameters[#workoutId]!);
}

Future<Workout> patchWorkoutById(Request request, String workoutId) async {
  final input = await WorkoutPatchIn.fromRequest(request);
  return request.workoutsService.patchWorkout(
    userId: request.userId,
    workoutId: workoutId,
    name: input.name,
    start: input.start,
    end: input.end,
    calories: input.calories,
    note: input.note,
    pauses: input.pauses,
    imageUrl: request.config.cdnAssetUrl,
  );
}

Future<NoContent> deleteWorkout(Request request) async {
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
