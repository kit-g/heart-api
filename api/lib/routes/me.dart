import 'dart:convert';

import 'package:heart/core/handler.dart';
import 'package:heart/globals/config.dart';
import 'package:heart/globals/globals.dart';
import 'package:heart/inputs/inputs.dart';
import 'package:heart/middleware/database.dart';
import 'package:heart/models/errors.dart';
import 'package:heart/models/exercises.dart';
import 'package:heart/models/exports.dart';
import 'package:heart/models/goals.dart';
import 'package:heart/models/me.dart';
import 'package:heart/models/pagination.dart';
import 'package:heart/models/template_folders.dart';
import 'package:heart/middleware/s3.dart';
import 'package:heart/routes/exercises.dart' as exercises;
import 'package:heart/routes/goals.dart' as goals;
import 'package:heart/routes/template_folders.dart' as folders;
import 'package:heart/routes/templates.dart' as templates;
import 'package:heart_models/heart_models.dart';
import 'package:relic/relic.dart';

// The read surface for personal access tokens (heart-api#112): caller-scoped,
// read-only, additive-only. Where the app's own handler already returns the
// right shape for the caller, it is reused as is.

Future<MeProfile> getMe(Request req) async {
  final user = await req.profileService.getProfile(req.userId);
  if (user == null) throw NotFound(type: 'profile', id: req.userId);
  final summary = await req.profileService.getAccountSummary(req.userId);
  return MeProfile(user: user, summary: summary);
}

Future<Paginated<MeWorkout>> getMyWorkouts(Request req) async {
  final query = PageQuery.fromRequest(req);
  final page = await req.workoutsService.getWorkouts(
    userId: req.userId,
    targetUserId: req.userId,
    limit: query.limit,
    cursor: query.cursor,
    imageUrl: req.config.cdnAssetUrl,
  );
  return Paginated<MeWorkout>.from(
    Page(items: page.items.map(MeWorkout.new).toList(), hasMore: page.hasMore),
    itemsKey: 'workouts',
    cursorOf: (w) => w.id,
  );
}

Future<MeWorkout> getMyWorkout(Request req) => getMyWorkoutById(req, req.rawPathParameters[#workoutId]!);

Future<MeWorkout> getMyWorkoutById(Request req, String workoutId) async {
  if (!isUuidV7(workoutId)) throw NotFound(type: 'Workout', id: workoutId);
  final workout = await req.workoutsService.getWorkout(
    userId: req.userId,
    workoutId: workoutId,
    imageUrl: req.config.cdnAssetUrl,
  );
  return MeWorkout(workout);
}

/// The caller's own exercises; catalog exercises arrive embedded in workouts
/// and templates, so there is nothing else to look up.
Future<ExerciseResponse> getMyExercises(Request req) => exercises.getExercises(req, owned: true);

Future<Paginated<Template>> getMyTemplates(Request req) => templates.getMyTemplates(req);

Future<TemplateFoldersResponse> getMyFolders(Request req) => folders.getMyFolders(req);

/// Goal definitions. Health-backed goals carry no progress here because the
/// server never has any: it's computed on the device.
Future<GoalsResponse> getMyGoals(Request req) => goals.getTargetUserGoalsById(
  req,
  req.userId,
  archived: GoalsQuery.fromRequest(req).archived,
);

/// Larger than this, an export goes out through a presigned link instead of
/// the response body, which Lambda caps at 6 MB.
const _inlineExportLimit = 5 * 1024 * 1024;

/// The whole account in another app's format: one a day, since it reads every
/// workout. Small ones come back as the body, large ones as a `303` to a
/// short-lived link.
Future<Model> exportMe(Request req, {int inlineLimit = _inlineExportLimit}) async {
  final format = ExportQuery.fromRequest(req).format;

  if (await req.apiTokenService.claimExport(req.userId) case final last?) {
    final wait = last.add(const Duration(days: 1)).difference(DateTime.now().toUtc());
    throw TooManyRequests(
      code: 'export_limit',
      reason: 'one export a day',
      retryAfter: wait.inSeconds.clamp(1, 86400),
    );
  }

  final user = await req.profileService.getProfile(req.userId);
  final workouts = await _everyWorkout(req);
  final csv = switch (format) {
    .strong => strongCsv(workouts, unit: user?.settings.unitSystem ?? .metric),
  };
  final bytes = utf8.encode(csv);
  final filename = 'heart-${format.name}.${format.extension}';

  if (bytes.length <= inlineLimit) {
    return Download(bytes: bytes, mimeType: .csv, filename: filename);
  }
  final link = await req.exportStorage.stash(
    key: 'exports/${uuidV7()}/$filename',
    bytes: bytes,
    mimeType: format.mimeType,
  );
  return SeeOther(link);
}

/// Every workout the caller owns, oldest first, as an export file lists them.
Future<List<Workout>> _everyWorkout(Request req) async {
  final all = <Workout>[];
  String? cursor;
  do {
    final page = await req.workoutsService.getWorkouts(
      userId: req.userId,
      targetUserId: req.userId,
      limit: 100,
      cursor: cursor,
      imageUrl: (key) => key,
    );
    all.addAll(page.items);
    cursor = page.hasMore ? page.items.last.id : null;
  } while (cursor != null);
  return all.reversed.toList();
}
