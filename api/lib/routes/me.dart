import 'dart:convert';

import 'package:heart/core/handler.dart';
import 'package:heart/core/request.dart';
import 'package:heart/globals/config.dart';
import 'package:heart/globals/globals.dart';
import 'package:heart/inputs/inputs.dart';
import 'package:heart/middleware/database.dart';
import 'package:heart/models/anomalies.dart';
import 'package:heart/models/changes.dart';
import 'package:heart/models/errors.dart';
import 'package:heart/models/exercises.dart';
import 'package:heart/models/exports.dart';
import 'package:heart/models/goals.dart';
import 'package:heart/models/lens.dart';
import 'package:heart/models/library.dart';
import 'package:heart/models/me.dart';
import 'package:heart/models/pagination.dart';
import 'package:heart/models/programs.dart';
import 'package:heart/models/template_folders.dart';
import 'package:heart/middleware/s3.dart';
import 'package:heart/routes/anomalies.dart' as anomalies;
import 'package:heart/routes/exercises.dart' as exercises;
import 'package:heart/routes/goals.dart' as goals;
import 'package:heart/routes/library.dart' show libraryView;
import 'package:heart/routes/programs.dart' as programs;
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

Future<Paginated<MeWorkout>> getMyWorkouts(Request req, PageQuery query) async {
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

Future<MeWorkout> getMyWorkout(Request req, String workoutId) async {
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

/// Each live goal with where it stands now, measured as the app measures it.
Future<MeGoalProgress> getMyGoalProgress(Request req) => goalProgress(req);

/// [MeGoalProgress] as of now, the route's and the MCP tool's both. Reads
/// only what the goals need: all time's sets for any but a workouts goal, all
/// time's workouts for one.
Future<MeGoalProgress> goalProgress(Request req) async {
  final (user, goals) = await (
    req.profileService.getProfile(req.userId),
    req.goalService.getTargetUserGoals(requesterId: req.userId, targetUserId: req.userId),
  ).wait;
  final weekStart = user?.settings.firstWeekday ?? DateTime.monday;
  final bySets = goals.any((goal) => !goal.metric.isWholeWorkout);
  final byWorkouts = goals.any((goal) => goal.metric.isWholeWorkout);
  final (sets, library, spans, pending) = await (
    bySets ? req.workoutsService.getRecordSets(userId: req.userId) : Future.value(const <ExerciseRecordSets>[]),
    bySets ? req.exerciseService.getExercises(req.userId) : Future.value(const <String, dynamic>{}),
    byWorkouts ? req.workoutsService.getWorkoutSpans(userId: req.userId) : Future.value(const <WorkoutSpan>[]),
    bySets ? req.anomalyService.getPendingAnomalies(userId: req.userId) : Future.value(const <Anomaly>[]),
  ).wait;
  return MeGoalProgress.measure(
    goals,
    now: DateTime.timestamp(),
    weekStart: weekStart,
    sets: sets,
    rows: sets.toLensRows(library),
    spans: spans,
    library: library,
    pending: pending,
  );
}

/// The user's suspicious entries, newest found first; `?status=` for one kind.
/// Read-only here: deciding is the app's.
Future<Paginated<Anomaly>> getMyAnomalies(Request req) => anomalies.getAnomalies(req);

/// The user's programs, each with where they stand in it.
Future<MePrograms> getMyPrograms(Request req) async {
  final all = await req.programService.getPrograms(req.userId);
  return MePrograms(
    await Future.wait([
      for (final program in all)
        programs.programState(req, program).then((state) => MeProgram(program, state.position)),
    ]),
  );
}

Future<MeProgram> getMyProgram(Request req) => getMyProgramById(req, req.rawPathParameters[#programId]!);

/// One program with where the user stands in it, each exercise's current
/// base, the next session planned from them, and, for a copy of a library
/// program, the research behind it.
Future<MeProgram> getMyProgramById(Request req, String programId) async {
  final program = await _myProgram(req, programId);
  final state = await programs.programState(req, program, withBases: true);
  final (:position, :bases, :stages) = state;
  if (program.source == null) {
    final next = await programs.nextSession(req, program, state);
    return MeProgram(program, position, bases: bases, stages: stages, nextSession: next);
  }
  final (sessions, view) = await (programs.programSessions(req, program), libraryView(req)).wait;
  return MeProgram(
    program,
    position,
    bases: bases,
    stages: stages,
    nextSession: await programs.nextSession(req, program, state, templates: sessions.nonNulls),
    research: view?.researchFor(program, sessions),
  );
}

/// The program library: every program with the facts that help choose one.
/// Empty while none is published.
Future<LibraryResponse> getMyLibraryPrograms(Request req) async {
  final view = await libraryView(req, named: false);
  return LibraryResponse({'programs': view?.list() ?? const []});
}

/// One library program in full, by its key.
Future<LibraryResponse> getMyLibraryProgram(Request req, String key) async {
  return switch ((await libraryView(req))?.program(key)) {
    final Map<String, dynamic> program => LibraryResponse(program),
    null => throw NotFound(type: 'LibraryProgram', id: key, code: 'library_program_not_found'),
  };
}

Future<ProgramHistory> getMyProgramHistory(Request req) async {
  final program = await _myProgram(req, req.rawPathParameters[#programId]!);
  return programs.programHistory(req, program);
}

Future<Program> _myProgram(Request req, String programId) {
  if (!isUuidV7(programId)) throw NotFound(type: 'Program', id: programId, code: 'program_not_found');
  return req.programService.getProgram(userId: req.userId, programId: programId);
}

/// Larger than this, an export goes out through a presigned link instead of
/// the response body, which Lambda caps at 6 MB.
const _inlineExportLimit = 5 * 1024 * 1024;

/// The whole account in another app's format: one a day, since it reads every
/// workout. Small ones come back as the body, large ones as a `303` to a
/// short-lived link.
Future<Model> exportMe(Request req, ExportQuery query, {int inlineLimit = _inlineExportLimit}) async {
  final format = query.format;

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

/// The change feed: what changed or was deleted since a cursor, oldest first.
/// A change waits until no save that started before it is still running.
Future<MeWorkoutChanges> getMyWorkoutChanges(Request req, ChangesQuery query) async {
  final changes = await req.workoutsService.getWorkoutChanges(
    userId: req.userId,
    since: query.since,
    limit: query.limit,
    imageUrl: req.config.cdnAssetUrl,
  );
  return MeWorkoutChanges(changes);
}

/// One exercise's sessions, newest first, optionally within `?from=&to=`.
Future<Paginated<MeExerciseSession>> getMyExerciseHistory(Request req, ExerciseHistoryQuery query) async {
  final (history, pending) = await (
    req.workoutsService.getExerciseHistory(
      userId: req.userId,
      exerciseId: query.exerciseId,
      cursor: query.cursor,
      limit: query.limit,
      from: query.from,
      to: query.to,
    ),
    req.anomalyService.getPendingAnomalies(userId: req.userId, from: query.from, to: query.to),
  ).wait;
  final ExerciseHistory(:category, :sessions) = history ?? (throw NotFound(type: 'Exercise', id: query.exerciseId));
  final warnings = pending.onSessions(query.exerciseId, sessions.items);
  return Paginated<MeExerciseSession>.from(
    Page(
      items: [for (final session in sessions.items) MeExerciseSession(session, category)],
      hasMore: sessions.hasMore,
    ),
    itemsKey: 'sessions',
    cursorOf: (session) => session.workoutId,
    extra: {if (warnings.isNotEmpty) 'warnings': warnings.toWarnings()},
  );
}

Future<MeLibrarySearch> searchMyLibrary(Request req, LibrarySearchQuery query) async {
  final config = req.config;
  if (query.locale case final locale? when !config.supportedLocales.contains(locale)) {
    throw BadRequest(reason: 'locale must be one of ${config.supportedLocales.join(', ')}: $locale');
  }
  final library = await req.exerciseService.getExercises(
    req.userId,
    locale: query.locale ?? req.locale(config.supportedLocales, config.defaultLocale),
  );
  return MeLibrarySearch.fromLibrary(library, query.query, limit: query.limit);
}

/// Personal records per exercise; one exercise's with `?exerciseId=`, those
/// of a span with `?from=&to=`.
Future<MeRecords> getMyRecords(Request req, RecordsQuery query) async {
  final (sets, pending) = await (
    req.workoutsService.getRecordSets(
      userId: req.userId,
      exerciseId: query.exerciseId,
      from: query.from,
      to: query.to,
    ),
    req.anomalyService.getPendingAnomalies(userId: req.userId, from: query.from, to: query.to),
  ).wait;
  return MeRecords.fold(sets, pending: pending);
}

/// Working sets and sessions per muscle group and per movement pattern, week
/// by week, and the groups nothing reached; within `?from=&to=`.
Future<MeVolume> getMyVolume(Request req) {
  final query = LensQuery.read(.of(req));
  return volume(req, from: query.from, to: query.to);
}

/// Each balance pair's two sides set against each other, within `?from=&to=`.
Future<MeBalance> getMyBalance(Request req) {
  final query = LensQuery.read(.of(req));
  return balance(req, from: query.from, to: query.to);
}

/// [MeVolume] over the weeks [from] and [to] reach, the route's and the MCP
/// tool's both.
Future<MeVolume> volume(Request req, {DateTime? from, DateTime? to}) async {
  final (:window, :rows, :pending, :spans) = await _lens(req, from: from, to: to, spans: true);
  return MeVolume.fold(window, rows, spans: spans, warnings: pending);
}

/// [MeBalance] over the weeks [from] and [to] reach, the route's and the MCP
/// tool's both. No pairs while none are published.
Future<MeBalance> balance(Request req, {DateTime? from, DateTime? to}) async {
  final ((:window, :rows, :pending, spans: _), content) = await (
    _lens(req, from: from, to: to),
    req.balancePairs.readPairs(),
  ).wait;
  final locale = req.locale(req.config.supportedLocales, req.config.defaultLocale);
  return MeBalance.fold(
    window,
    rows,
    content: content,
    locale: locale,
    // a duration doesn't move a balance
    warnings: [
      for (final anomaly in pending)
        if (anomaly.setId != null) anomaly,
    ],
  );
}

/// The window, in the user's weeks, the working sets in it with what each
/// exercise trains, and the pending anomalies among them; the workouts' spans
/// too when [spans].
Future<_Lens> _lens(Request req, {DateTime? from, DateTime? to, bool spans = false}) async {
  final user = await req.profileService.getProfile(req.userId);
  final window = LensWindow.resolve(weekStart: user?.settings.firstWeekday ?? DateTime.monday, from: from, to: to);
  final (sets, library, pending, workoutSpans) = await (
    req.workoutsService.getRecordSets(userId: req.userId, from: window.from, to: window.to),
    req.exerciseService.getExercises(req.userId),
    req.anomalyService.getPendingAnomalies(userId: req.userId, from: window.from, to: window.to),
    spans
        ? req.workoutsService.getWorkoutSpans(userId: req.userId, from: window.from, to: window.to)
        : Future.value(const <WorkoutSpan>[]),
  ).wait;
  return (window: window, rows: sets.toLensRows(library), pending: pending, spans: workoutSpans);
}

typedef _Lens = ({LensWindow window, List<LensRow> rows, List<Anomaly> pending, List<WorkoutSpan> spans});
