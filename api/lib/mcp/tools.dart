import 'package:heart/core/request.dart';
import 'package:heart/globals/config.dart';
import 'package:heart/globals/globals.dart';
import 'package:heart/middleware/database.dart';
import 'package:heart/middleware/s3.dart';
import 'package:heart/models/changes.dart';
import 'package:heart/models/errors.dart';
import 'package:heart/models/lens.dart';
import 'package:heart/models/me.dart';
import 'package:heart/models/workouts.dart';
import 'package:heart/models/library.dart';
import 'package:heart/routes/library.dart' show libraryView;
import 'package:heart/routes/me.dart' as me;
import 'package:heart/routes/programs.dart' as programs;
import 'package:heart_models/heart_models.dart';
import 'package:relic/relic.dart';

/// A tool the model can call. Everything here is read-only and backed by a
/// `/me` route's service call: the MCP server never knows something the
/// developer API can't tell.
class McpTool {
  final String name;
  final String title;
  final String description;
  final Map<String, dynamic> inputSchema;
  final Future<Map<String, dynamic>> Function(Request request, Map<String, dynamic> arguments) run;

  const new({
    required this.name,
    required this.title,
    required this.description,
    this.inputSchema = const {'type': 'object', 'properties': <String, dynamic>{}, 'additionalProperties': false},
    required this.run,
  });

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'title': title,
      'description': description,
      'inputSchema': inputSchema,
      'annotations': {
        'title': title,
        'readOnlyHint': true,
        'destructiveHint': false,
        'idempotentHint': true,
        'openWorldHint': false,
      },
    };
  }
}

/// A tool call that can't be answered as asked: reported to the model as a
/// tool error it can act on, not as a protocol failure.
class ToolError implements Exception {
  final String message;

  const new(this.message);
}

/// What the model is told about the server as a whole.
const instructions =
    "Heart is the user's workout log: workouts, sets, templates, goals and custom exercises. "
    'It has no health data: no heart rate, sleep, steps or body weight from the health store, because '
    'that never leaves the user\'s phone. Do not offer to look it up. Workout calories, where present, '
    'are an estimate, not a measurement. Weights are in kilograms and distances in kilometres; convert '
    "to the user's unitSystem from get_profile when answering. Lists are paged: pass back `cursor` while "
    'one is returned. Everything here is read-only.';

final List<McpTool> tools = [
  McpTool(
    name: 'get_profile',
    title: 'Profile',
    description: "The user's name, preferred units, and how much history there is to read.",
    run: (request, _) async {
      final user = await request.profileService.getProfile(request.userId);
      final summary = await request.profileService.getAccountSummary(request.userId);
      return {
        'username': ?user?.displayName,
        'unitSystem': user?.settings.unitSystem?.name ?? 'metric',
        'counts': {
          'workouts': summary[.workouts].count,
          'templates': summary[.templates].count,
          'goals': summary[.goals].count,
          'customExercises': summary[.customExercises].count,
        },
      };
    },
  ),
  McpTool(
    name: 'list_workouts',
    title: 'List workouts',
    description:
        'Workouts newest first, as summaries: name, date, duration, and per exercise the number of '
        'completed sets and the best set. Use get_workout for every set of one workout.',
    inputSchema: _pageSchema(maxLimit: 50),
    run: (request, arguments) async {
      final (limit, cursor) = arguments.toPaging(defaultLimit: 20, maxLimit: 50);
      if (cursor != null && !isUuidV7(cursor)) {
        throw const ToolError('cursor must be the string returned by the previous page.');
      }
      final page = await request.workoutsService.getWorkouts(
        userId: request.userId,
        targetUserId: request.userId,
        limit: limit,
        cursor: cursor,
        imageUrl: request.config.cdnAssetUrl,
      );
      return {
        'workouts': [for (final workout in page.items) workout.toMcpSummary()],
        if (page.hasMore) 'cursor': page.items.last.id,
      };
    },
  ),
  McpTool(
    name: 'get_workout',
    title: 'Get a workout',
    description: 'One workout in full: every exercise and set, with set types, RPE and notes.',
    inputSchema: {
      'type': 'object',
      'properties': {
        'workoutId': {'type': 'string', 'description': 'An id from list_workouts.'},
      },
      'required': ['workoutId'],
      'additionalProperties': false,
    },
    run: (request, arguments) async {
      final id = arguments['workoutId'];
      if (id is! String || !isUuidV7(id)) throw const ToolError('workoutId must be an id from list_workouts.');
      try {
        final workout = await request.workoutsService.getWorkout(
          userId: request.userId,
          workoutId: id,
          imageUrl: request.config.cdnAssetUrl,
        );
        return workout.toMcpDetail();
      } on NotFound {
        throw ToolError('No workout $id. Use list_workouts for valid ids.');
      }
    },
  ),
  McpTool(
    name: 'get_personal_records',
    title: 'Personal records',
    description:
        'Personal records per exercise, the same ones the app shows: heaviest set, estimated 1RM (Brzycki), '
        'best volume set, rep maxes, most reps, longest distance or duration, best pace (seconds per km), with '
        'the date and workout each was set in and what it beat. A rep max is the heaviest set of exactly that '
        'many reps, so a higher count can be heavier. Weights in kg, distances in km, durations in seconds. '
        'Exercises come by name, a page at a time: pass `exercise` to narrow to names containing that text, or '
        'the returned cursor for the next page. Pass `from` and `to` for the records of a span ("heaviest this '
        'year"): only workouts started in it count, and what a record beat is from the same span.',
    inputSchema: {
      'type': 'object',
      'properties': {
        'exercise': {'type': 'string', 'description': 'Part of an exercise name, case-insensitive.'},
        ..._windowSchema,
        ..._pageSchema(maxLimit: 50)['properties'] as Map<String, dynamic>,
      },
      'additionalProperties': false,
    },
    run: (request, arguments) async {
      final filter = switch (arguments['exercise']) {
        final String text when text.trim().isNotEmpty => text.trim().toLowerCase(),
        null => null,
        _ => throw const ToolError('exercise must be text, part of an exercise name.'),
      };
      final (limit, cursor) = arguments.toPaging(defaultLimit: 20, maxLimit: 50);
      final (:from, :to) = arguments.toWindow();
      final sets = await request.workoutsService.getRecordSets(userId: request.userId, from: from, to: to);
      final matching = [
        for (final exercise in sets)
          if (filter == null || exercise.name.toLowerCase().contains(filter)) exercise,
      ];
      final MeRecords(:entries) = MeRecords.fold(matching);
      if (filter != null && entries.isEmpty) {
        throw ToolError('No records for an exercise matching "$filter". list_workouts shows exercise names.');
      }
      final start = switch (cursor) {
        null => 0,
        final id => switch (entries.indexWhere((entry) => entry.exercise.exerciseId == id)) {
          -1 => throw const ToolError('cursor must be the string returned by the previous page.'),
          final index => index + 1,
        },
      };
      final page = entries.skip(start).take(limit).toList();
      return {
        'records': [
          for (final (:exercise, :records) in page)
            {
              'exercise': {'id': exercise.exerciseId, 'name': exercise.name, 'category': exercise.category.value},
              ...records.toMcpUnits() as Map<String, dynamic>,
            },
        ],
        if (start + page.length < entries.length) 'cursor': page.last.exercise.exerciseId,
      };
    },
  ),
  McpTool(
    name: 'get_exercise_history',
    title: 'Exercise history',
    description:
        "One exercise's sessions, newest first: the working sets of each, and the values the app's progress "
        'chart plots for it (top set, estimated 1RM by Brzycki, volume, average working weight, reps; distance, '
        'duration and pace for cardio). Weights in kg, distances in km, durations in seconds, pace in seconds per '
        'km. Exercise ids come from get_workout or get_personal_records. Paged: pass the returned cursor for older '
        'sessions. `from` and `to` keep to workouts started in that span.',
    inputSchema: {
      'type': 'object',
      'properties': {
        'exerciseId': {'type': 'string', 'description': 'An exercise id from get_workout or get_personal_records.'},
        ..._windowSchema,
        ..._pageSchema(maxLimit: 50)['properties'] as Map<String, dynamic>,
      },
      'required': ['exerciseId'],
      'additionalProperties': false,
    },
    run: (request, arguments) async {
      final id = arguments['exerciseId'];
      if (id is! String || !isUuidV7(id)) {
        throw const ToolError('exerciseId must be an id from get_workout or get_personal_records.');
      }
      final (limit, cursor) = arguments.toPaging(defaultLimit: 20, maxLimit: 50);
      if (cursor != null && !isUuidV7(cursor)) {
        throw const ToolError('cursor must be the string returned by the previous page.');
      }
      final (:from, :to) = arguments.toWindow();
      final history =
          await request.workoutsService.getExerciseHistory(
            userId: request.userId,
            exerciseId: id,
            cursor: cursor,
            limit: limit,
            from: from,
            to: to,
          ) ??
          (throw ToolError('No exercise $id. get_personal_records lists the exercises with history.'));
      final ExerciseHistory(:exerciseId, :name, :category, :sessions) = history;
      return {
        'exercise': {'id': exerciseId, 'name': name, 'category': category.value},
        'sessions': [
          for (final session in sessions.items)
            {
              'workoutId': session.workoutId,
              'at': session.at,
              'sets': [for (final set in session.sets) set.toMcp()],
              'metrics': session.sets.toSessionMetrics(category).toMcpUnits(),
            },
        ],
        if (sessions.hasMore && sessions.items.isNotEmpty) 'cursor': sessions.items.last.workoutId,
      };
    },
  ),
  McpTool(
    name: 'get_training_volume',
    title: 'Training volume',
    description:
        'Working sets (warm-ups left out) and sessions per muscle group and per movement pattern, week by week: '
        'what the app counts on its weekly card. A set counts fully for the muscles an exercise works first and '
        'partly (usually half) for the ones it works second, so sets per muscle may be fractional; round them '
        'when answering. An exercise the user made counts toward the group its target names and the pattern they '
        'gave it. untrained lists the muscle groups no set reached in the whole span ("which muscles did I skip"). '
        'Weeks start on weekStart (ISO, 1 Monday) in UTC. Without `from`, the 4 weeks ending this one; at most a '
        'year.',
    inputSchema: const {
      'type': 'object',
      'properties': _windowSchema,
      'additionalProperties': false,
    },
    run: (request, arguments) async {
      final (:from, :to) = arguments.toLensWindow();
      return (await me.volume(request, from: from, to: to)).toMap();
    },
  ),
  McpTool(
    name: 'get_balance',
    title: 'Balance',
    description:
        "Opposing movements set against each other, the app's balance view: push against pull, hinge against "
        'squat, curls against triceps extensions, leg extensions against leg curls. Per pair, the working sets of '
        'each side (an exercise counts toward a side when one of its movement patterns is on it) and in how many '
        'of the weeks either side was trained. Counts only: Heart draws no conclusion from them, and a few weeks of '
        'a handful of sets say little. Weeks and the span as in get_training_volume.',
    inputSchema: const {
      'type': 'object',
      'properties': _windowSchema,
      'additionalProperties': false,
    },
    run: (request, arguments) async {
      final (:from, :to) = arguments.toLensWindow();
      final balance = (await me.balance(request, from: from, to: to)).toMap();
      if ((balance['pairs'] as List).isEmpty) return {...balance, 'note': 'The balance pairs are not published yet.'};
      return balance;
    },
  ),
  McpTool(
    name: 'search_exercises',
    title: 'Search exercises',
    description:
        "The exercise library and the user's own exercises, searched the way the app searches: word order free, "
        'gym abbreviations (db, rdl, ohp), muscle words (lats, quads) and one typo per word. Best matches first; '
        '`match` says how each was found. Names come in `locale`, the language the user writes in (default '
        'English); category and target are fixed English identifiers in every locale.',
    inputSchema: {
      'type': 'object',
      'properties': {
        'query': {'type': 'string', 'description': 'What to look for, as the user would type it.'},
        'locale': {'type': 'string', 'description': 'A language code such as es or fr; regional ones like fr_CA too.'},
        'limit': {'type': 'integer', 'minimum': 1, 'maximum': 50},
      },
      'required': ['query'],
      'additionalProperties': false,
    },
    run: (request, arguments) async {
      final query = switch (arguments['query']) {
        final String text when text.trim().isNotEmpty && text.trim().length <= 100 => text.trim(),
        _ => throw const ToolError('query must be text, up to 100 characters.'),
      };
      final locale = switch (arguments['locale']) {
        null => request.config.defaultLocale,
        final String locale when request.config.supportedLocales.contains(locale) => locale,
        _ => throw ToolError('locale must be one of ${request.config.supportedLocales.join(', ')}.'),
      };
      final (limit, _) = arguments.toPaging(defaultLimit: 20, maxLimit: 50);
      final library = await request.exerciseService.getExercises(request.userId, locale: locale);
      final results = MeLibrarySearch.fromLibrary(library, query, limit: limit);
      if (results.results.isEmpty) {
        throw ToolError('Nothing in the library matches "$query". Try fewer or more common words.');
      }
      return results.toMap();
    },
  ),
  McpTool(
    name: 'list_templates',
    title: 'List templates',
    description: "The user's workout templates in their own order, with each template's exercises and set count.",
    inputSchema: _pageSchema(maxLimit: 100),
    run: (request, arguments) async {
      final (limit, cursor) = arguments.toPaging(defaultLimit: 50, maxLimit: 100);
      final ordered = switch (cursor) {
        final String raw =>
          OrderedCursor.tryParse(raw) ??
              (throw const ToolError('cursor must be the string returned by the previous page.')),
        null => null,
      };
      final page = await request.templatesService.getTemplates(userId: request.userId, limit: limit, cursor: ordered);
      return {
        'templates': [
          for (final template in page.items)
            {
              'id': template.id,
              'name': template.name ?? 'Untitled',
              'folderId': ?template.folderId,
              'exercises': [
                for (final exercise in template) {'name': exercise.exercise.name, 'sets': exercise.length},
              ],
            },
        ],
        if (page.hasMore) 'cursor': OrderedCursor(order: page.items.last.order, id: page.items.last.id).toString(),
      };
    },
  ),
  McpTool(
    name: 'list_template_folders',
    title: 'List template folders',
    description: 'The folders templates are filed in, with how many each holds.',
    run: (request, _) async {
      final folders = await request.templateFolderService.getFolders(userId: request.userId);
      return {
        'folders': [
          for (final folder in folders) {'id': folder.id, 'name': folder.name, 'templates': ?folder.templateCount},
        ],
      };
    },
  ),
  McpTool(
    name: 'list_goals',
    title: 'List goals',
    description:
        "The user's goals: what is measured, the targets and deadlines, and which stages are achieved (a stage "
        'carries achievedAt only once it is). A goal on an exercise names it; one on a movement pattern or a muscle '
        'carries that key as pattern or muscle. Goals on health metrics carry their '
        'definition only; their progress lives on the phone.',
    inputSchema: {
      'type': 'object',
      'properties': {
        'archived': {'type': 'boolean', 'description': 'List archived goals instead of active ones.'},
      },
      'additionalProperties': false,
    },
    run: (request, arguments) async {
      final goals = await request.goalService.getTargetUserGoals(
        requesterId: request.userId,
        targetUserId: request.userId,
        archived: arguments['archived'] == true,
      );
      final names = switch (goals.any((goal) => goal.exerciseId != null)) {
        true => (await request.exerciseService.getExercises(request.userId)).toExerciseNames(),
        false => const <String, String>{},
      };
      return {
        'goals': [
          for (final goal in goals) {...goal.toMap(), 'exerciseName': ?names[goal.exerciseId]},
        ],
      };
    },
  ),
  McpTool(
    name: 'list_programs',
    title: 'List programs',
    description:
        "The user's programs: plans of their templates, done in any order on any day, whose targets grow. Each "
        'shows where the user stands: the program week (it moves when every session of a cycle is done or skipped, '
        'never by the calendar), the next session, whether it is paused or finished, and workouts this week against '
        'the weekly target. Weeks here are ISO weeks in UTC.',
    run: (request, _) async {
      final all = await request.programService.getPrograms(request.userId);
      return {
        'programs': [
          for (final program in all)
            {
              'id': program.id,
              'name': program.name,
              'archived': program.archived,
              'sessions': program.sessions.length,
              if (program.weeks case final int weeks) 'weeks': weeks,
              'perWeek': ?program.perWeek,
              ...(await programs.programState(request, program)).position.toMap()
                ..remove('done')
                ..remove('remaining'),
            },
        ],
      };
    },
  ),
  McpTool(
    name: 'get_program',
    title: 'Get a program',
    description:
        'One program in full: its sessions in order with which are done in the open cycle, the next one, and each '
        "exercise's growth rule and current base. A base is the number the rule grows: a training max or working "
        'weight in kg, a duration in seconds, a distance in km. A lift used in two sessions (heavy one day, light '
        'another) may keep a rule, a base and a stage per session, under slots. A stages rule moves through set '
        'schemes on a miss; stage is the one it is on, from 0. The position is computed from the workouts and skips '
        'the user logged against the program, never stored. nextSession is the session up next as the app will '
        "show it: this week's targets, weights worked out from the current bases (a share of a base, rounded down "
        'to the rule step; a lighter week at its deload share), and no weights in a test session, which is how a '
        'base is found. It reads what is stored; it is not a forecast. get_program_history explains how bases moved. '
        'A program started from the library (source) carries research: the claims behind it with their sources, '
        'each placed on the part it explains.',
    inputSchema: {
      'type': 'object',
      'properties': {
        'programId': {'type': 'string', 'description': 'An id from list_programs.'},
      },
      'required': ['programId'],
      'additionalProperties': false,
    },
    run: (request, arguments) async {
      final id = arguments['programId'];
      if (id is! String || !isUuidV7(id)) throw const ToolError('programId must be an id from list_programs.');
      final Program program;
      try {
        program = await request.programService.getProgram(userId: request.userId, programId: id);
      } on NotFound {
        throw ToolError('No program $id. Use list_programs for valid ids.');
      }
      final state = await programs.programState(request, program, withBases: true);
      final (:position, :bases, :stages) = state;
      final library = await request.exerciseService.getExercises(request.userId);
      final names = library.toExerciseNames();
      final (templates, view) = await (
        programs.programSessions(request, program),
        switch (program.source) {
          // the research anchors by id, so the library already read will do
          String() => libraryView(request, library: library),
          null => Future<LibraryView?>.value(),
        },
      ).wait;
      // the session each template exercise is in, for a base kept per slot
      final sessionOf = {
        for (final template in templates.nonNulls)
          for (final exercise in template) exercise.id: template.name ?? 'Untitled',
      };
      // and the exercise each slot is, for a rule kept per slot
      final exerciseOf = {
        for (final template in templates.nonNulls)
          for (final exercise in template) exercise.id: exercise.exercise.id,
      };
      final next = await programs.nextSession(request, program, state, templates: templates.nonNulls);
      return {
        'id': program.id,
        'name': program.name,
        'note': ?program.note,
        'perWeek': ?program.perWeek,
        'weeks': ?program.weeks,
        'archived': program.archived,
        'position': {
          ...position.toMap()
            ..remove('done')
            ..remove('remaining'),
        },
        'sessions': [
          for (final template in templates.nonNulls)
            {
              'id': template.id,
              'name': template.name ?? 'Untitled',
              'note': ?template.note,
              'done': position.done.contains(template.id),
              'exercises': [for (final exercise in template) exercise.exercise.name],
            },
        ],
        'exercises': [
          for (final exerciseId in {
            // a key is a slot's or an exercise's; a slot whose session is gone
            // names nothing left to show
            for (final key in program.rules.keys)
              if (exerciseOf[key] ?? (names.containsKey(key) ? key : null) case final String exercise) exercise,
            for (final base in bases.values) base.exerciseId,
          })
            {
              'name': names[exerciseId] ?? exerciseId,
              'rule': ?program.rules[exerciseId]?.toMap(),
              if (bases[exerciseId] case final ProgramBase base) 'base': base.value,
              'stage': ?stages[exerciseId],
              // a lift used twice may keep a rule, a base and a stage per
              // occurrence, keyed by its slot
              if ([
                    for (final MapEntry(key: slot, value: exercise) in exerciseOf.entries)
                      if (exercise == exerciseId &&
                          (program.rules.containsKey(slot) || bases.containsKey(slot) || stages.containsKey(slot)))
                        {
                          'session': ?sessionOf[slot],
                          'rule': ?program.rules[slot]?.toMap(),
                          'base': ?bases[slot]?.value,
                          'stage': ?stages[slot],
                        },
                  ]
                  case final slots when slots.isNotEmpty)
                'slots': slots,
            },
        ],
        if (view?.researchFor(program, templates) case final Map<String, dynamic> research)
          'research': _namedResearch(research, templates: templates.nonNulls, names: names),
        if (next != null)
          'nextSession': _namedPlan(
            next,
            session: templates.nonNulls.firstWhere((template) => template.id == next.templateId).name ?? 'Untitled',
            names: names,
            sessions: sessionOf,
          ),
      };
    },
  ),
  McpTool(
    name: 'get_program_history',
    title: "Get a program's history",
    description:
        "How a program got where it is: every value of each exercise's base, oldest first, with what caused it "
        '(workout: a session grew it, or cut it after misses when it went down; test: a test session set it; '
        'action: replaying a week set it; user: the user set it) and the value before it. Also the steps the user '
        'took (pause, resume, repeat, replay, a lighter week, a ladder moving to its next exercise, a stages rule '
        'moving to another set scheme) and the sessions '
        'skipped, with the reason given. Bases are in kg, seconds or km, as in get_program.',
    inputSchema: {
      'type': 'object',
      'properties': {
        'programId': {'type': 'string', 'description': 'An id from list_programs.'},
      },
      'required': ['programId'],
      'additionalProperties': false,
    },
    run: (request, arguments) async {
      final id = arguments['programId'];
      if (id is! String || !isUuidV7(id)) throw const ToolError('programId must be an id from list_programs.');
      final Program program;
      try {
        program = await request.programService.getProgram(userId: request.userId, programId: id);
      } on NotFound {
        throw ToolError('No program $id. Use list_programs for valid ids.');
      }
      final (history, names, templates) = await (
        programs.programHistory(request, program),
        request.exerciseService.getExercises(request.userId).then((library) => library.toExerciseNames()),
        programs.programSessions(request, program),
      ).wait;
      final sessionNames = {for (final template in templates.nonNulls) template.id: template.name ?? 'Untitled'};
      final slotSessions = {
        for (final template in templates.nonNulls)
          for (final exercise in template) exercise.id: template.name ?? 'Untitled',
      };
      String name(String exerciseId) => names[exerciseId] ?? exerciseId;
      return {
        'bases': [
          for (final (:base, :cause, :previous) in history.bases)
            {
              'exercise': name(base.exerciseId),
              if (base.slot case final String slot) 'session': slotSessions[slot] ?? slot,
              'value': base.value,
              'previous': ?previous,
              'cause': cause.value,
              'at': base.at.toUtc().toIso8601String(),
            },
        ],
        'actions': [
          for (final action in history.actions)
            {
              'kind': action.kind.value,
              'week': ?action.week,
              if (action.from case final String from) 'from': name(from),
              if (action.to case final String to) 'to': name(to),
              if (action.exercise case final String exercise) 'exercise': name(exercise),
              if (action.slot case final String slot) 'session': slotSessions[slot] ?? slot,
              'stage': ?action.stage,
              'at': action.at.toUtc().toIso8601String(),
            },
        ],
        'skips': [
          for (final skip in history.skips)
            {
              'at': skip.at.toUtc().toIso8601String(),
              'reason': ?skip.reason,
              if (skip.templateId case final String session) 'session': sessionNames[session] ?? session,
            },
        ],
      };
    },
  ),
  McpTool(
    name: 'list_library_programs',
    title: 'List library programs',
    description:
        "Heart's own ready-made programs, which anyone can start in the app: for each, who it is for (audience: "
        'starting_out, getting_back, keep_muscle, getting_stronger), the equipment it needs (none, home, gym), days '
        'a week, minutes a session and weeks long. Use get_library_program for one in full. Copy is in the '
        "user's language where translated, else English. Starting one happens in the app.",
    run: (request, _) async {
      final view = await libraryView(request, named: false);
      if (view == null) return {'programs': const [], 'note': 'The program library is not published yet.'};
      return {'programs': view.list()};
    },
  ),
  McpTool(
    name: 'get_library_program',
    title: 'Get a library program',
    description:
        'One library program in full: who it is for, what a week looks like, how it grows and what a missed '
        'session does; its sessions with their sets and targets (exercises by library key, named under '
        'exercises); its growth rules; the research behind it, each claim with its sources (title, authors, year, '
        'a link, and the finding in plain words) and the part of the program it explains (about); safety notes; '
        'and where to go next. A share in a target is of the training max. It describes the plan; it is not '
        'medical advice.',
    inputSchema: {
      'type': 'object',
      'properties': {
        'key': {'type': 'string', 'description': 'A key from list_library_programs.'},
      },
      'required': ['key'],
      'additionalProperties': false,
    },
    run: (request, arguments) async {
      final key = arguments['key'];
      if (key is! String) throw const ToolError('key must be a key from list_library_programs.');
      final program = (await libraryView(request))?.program(key);
      if (program == null) throw ToolError('No library program $key. Use list_library_programs for valid keys.');
      return program;
    },
  ),
  McpTool(
    name: 'list_custom_exercises',
    title: 'List custom exercises',
    description:
        'Exercises the user created themselves, with the movement pattern they gave one (such as horizontal_press), '
        'if any. Library exercises appear by name inside workouts and templates.',
    run: (request, _) async {
      final library = await request.exerciseService.getExercises(
        request.userId,
        locale: request.locale(request.config.supportedLocales, request.config.defaultLocale),
        owned: true,
      );
      return {
        'exercises': [
          for (final exercise in (library['exercises'] as List? ?? const []).cast<Map>())
            {
              'name': exercise['name'],
              'category': exercise['category'],
              'target': exercise['target'],
              // the movement pattern the user gave it (heart-api#269)
              if (exercise['movement'] case {'groups': [final String pattern, ...]}) 'pattern': pattern,
            },
        ],
      };
    },
  ),
];

/// [plan] for an assistant: exercises by name, and a share of another lift
/// naming that lift, and the session of the occurrence it is of.
Map<String, dynamic> _namedPlan(
  PlannedSession plan, {
  required String session,
  required Map<String, String> names,
  required Map<String, String> sessions,
}) {
  final map = plan.toMap();
  return {
    'session': session,
    'week': map['week'],
    'lighter': map['lighter'],
    'test': ?map['test'],
    'exercises': [
      for (final exercise in (map['exercises'] as List).cast<Map<String, dynamic>>())
        {
          'name': names[exercise['exerciseId']] ?? exercise['exerciseId'],
          'base': ?exercise['base'],
          'sets': [
            for (final set in (exercise['sets'] as List).cast<Map<String, dynamic>>())
              {
                ...set,
                if (set['target'] case final Map<String, dynamic> target)
                  'target': {
                    ...target,
                    if (target['of'] case final String of) 'of': names[of] ?? of,
                    if (target['ofSlot'] case final String slot) 'ofSlot': sessions[slot] ?? slot,
                  },
              },
          ],
        },
    ],
  };
}

/// [research] for an assistant: each claim's anchors name the session and
/// exercise they sit on instead of ids.
Map<String, dynamic> _namedResearch(
  Map<String, dynamic> research, {
  required Iterable<Template> templates,
  required Map<String, String> names,
}) {
  final sessions = {for (final template in templates) template.id: template};
  return {
    ...research,
    'claims': [
      for (final claim in (research['claims'] as List).cast<Map<String, dynamic>>())
        {
          ...claim,
          'about': [
            for (final about in (claim['about'] as List).cast<Map<String, dynamic>>())
              switch (about) {
                {'on': 'rule', 'exercise': final String id} => {'on': 'rule', 'exercise': names[id] ?? id},
                {'on': 'session', 'session': final String id} => {
                  'on': 'session',
                  'session': sessions[id]?.name ?? 'Untitled',
                },
                {'on': 'exercise', 'session': final String id, 'exercise': final String slot} => {
                  'on': 'exercise',
                  'session': sessions[id]?.name ?? 'Untitled',
                  'exercise': ?sessions[id]?.where((exercise) => exercise.id == slot).firstOrNull?.exercise.name,
                },
                _ => about,
              },
          ],
        },
    ],
  };
}

final Map<String, McpTool> toolsByName = {for (final tool in tools) tool.name: tool};

Map<String, dynamic> _pageSchema({required int maxLimit}) {
  return {
    'type': 'object',
    'properties': {
      'limit': {'type': 'integer', 'minimum': 1, 'maximum': maxLimit},
      'cursor': {'type': 'string', 'description': 'The cursor from the previous page.'},
    },
    'additionalProperties': false,
  };
}

/// `from` and `to`, a span of workout start times.
const _windowSchema = {
  'from': {'type': 'string', 'description': 'Start of the span, inclusive: a date (2026-01-01, UTC) or an ISO moment.'},
  'to': {'type': 'string', 'description': 'End of the span, exclusive: a date (2026-01-01, UTC) or an ISO moment.'},
};

extension on Map<String, dynamic> {
  /// A tool's `from` and `to` arguments, read: either may be absent; one that
  /// isn't a date or moment, or a `from` not before `to`, is refused.
  ({DateTime? from, DateTime? to}) toWindow() {
    DateTime? edge(String key) {
      return switch (this[key]) {
        null => null,
        final String raw =>
          raw.toWindowEdge() ?? (throw ToolError('$key must be a date like 2026-01-01 or an ISO moment.')),
        _ => throw ToolError('$key must be a date like 2026-01-01 or an ISO moment.'),
      };
    }

    final (from, to) = (edge('from'), edge('to'));
    if (from != null && to != null && !from.isBefore(to)) throw const ToolError('from must be before to.');
    return (from: from, to: to);
  }

  /// [toWindow] for a count over weeks, at most a year long.
  ({DateTime? from, DateTime? to}) toLensWindow() {
    final (:from, :to) = toWindow();
    if (from != null && (to ?? DateTime.timestamp()).difference(from) > LensWindow.longest) {
      throw const ToolError('from and to may be at most a year apart.');
    }
    return (from: from, to: to);
  }

  /// A tool's `limit` and `cursor` arguments, read: [defaultLimit] when the
  /// limit is absent, refused outside 1 to [maxLimit] like any bad argument.
  (int, String?) toPaging({required int defaultLimit, required int maxLimit}) {
    final limit = switch (this['limit']) {
      final int n when n >= 1 && n <= maxLimit => n,
      null => defaultLimit,
      _ => throw ToolError('limit must be a whole number from 1 to $maxLimit.'),
    };
    final cursor = switch (this['cursor']) {
      final String c when c.isNotEmpty => c,
      null => null,
      _ => throw const ToolError('cursor must be the string returned by the previous page.'),
    };
    return (limit, cursor);
  }
}

/// Workouts as the tools show them: sized for a model's context, units in
/// the key names, nothing internal.
extension on Workout {
  /// A row in `list_workouts`: each exercise with its completed sets and
  /// best set, not the sets themselves.
  Map<String, dynamic> toMcpSummary() {
    return {
      ..._toMcpHeader(),
      'minutes': ?end?.difference(start).inMinutes,
      'exercises': [
        for (final exercise in this)
          {
            'name': exercise.exercise.name,
            'completedSets': exercise.where((set) => set.isCompleted).length,
            'best': ?exercise.best?.toMcp(),
          },
      ],
    };
  }

  /// `get_workout`: every exercise and set.
  Map<String, dynamic> toMcpDetail() {
    return {
      ..._toMcpHeader(),
      'end': ?end?.toUtc().toIso8601String(),
      'note': ?note,
      'caloriesEstimate': ?calories?.round(),
      'exercises': [
        for (final exercise in this)
          {
            'id': exercise.exercise.id,
            'name': exercise.exercise.name,
            'note': ?exercise.note,
            'sets': [for (final set in exercise) set.toMcp()],
          },
      ],
    };
  }

  Map<String, dynamic> _toMcpHeader() {
    return {'id': id, 'name': ?name, 'start': start.toUtc().toIso8601String()};
  }
}

extension on ExerciseSet {
  /// A set as the tools show it: its type only when it isn't a normal set,
  /// `completed` only when it wasn't.
  Map<String, dynamic> toMcp() {
    return {
      'type': ?(setType == .normal ? null : setType.value),
      ...(weight: weight, reps: reps, distance: distance, duration: duration).toMcp(),
      'rpe': ?rpe,
      if (!isCompleted) 'completed': false,
    };
  }
}

extension on RecordSet {
  /// A set in an exercise's history: its measurements alone.
  Map<String, dynamic> toMcp() {
    return (weight: weight, reps: reps, distance: distance, duration: duration).toMcp();
  }
}

/// A set's measurements, whatever kind of set they come from.
typedef _Measures = ({num? weight, int? reps, num? distance, num? duration});

extension on _Measures {
  /// The one place the tools name their units.
  Map<String, dynamic> toMcp() {
    return {
      'weightKg': ?weight?.toMcpMeasure(),
      'reps': ?reps,
      'distanceKm': ?distance?.toMcpMeasure(),
      'seconds': ?duration?.toMcpMeasure(),
    };
  }
}

/// The unit-bearing keys of a shared fold's output, renamed as the tools
/// name them everywhere else.
const _unitKeys = {'weight': 'weightKg', 'distance': 'distanceKm', 'duration': 'seconds'};

extension on num {
  /// Three decimals: grams and metres, and a weight entered in pounds still
  /// converts back whole. Stored weights carry float noise past that.
  num toMcpMeasure() => this is int ? this : (this * 1000).round() / 1000;
}

extension on Object? {
  /// A fold's output (records, chart values) as the tools show it: unit keys
  /// renamed and every decimal rounded, at any depth.
  Object? toMcpUnits() {
    return switch (this) {
      final Map<dynamic, dynamic> map => <String, dynamic>{
        for (final MapEntry(:key, value: Object? value) in map.entries) _unitKeys[key] ?? '$key': value.toMcpUnits(),
      },
      final List<dynamic> list => [for (final Object? value in list) value.toMcpUnits()],
      final num n => n.toMcpMeasure(),
      final other => other,
    };
  }
}

extension on Map<String, dynamic> {
  /// The library's exercises by id, for naming what a goal points at.
  Map<String, String> toExerciseNames() {
    return {
      for (final row in this['exercises'] as List? ?? const [])
        if (row case {'id': final String id, 'name': final String name}) id: name,
    };
  }
}
