import 'package:heart/core/request.dart';
import 'package:heart/globals/config.dart';
import 'package:heart/globals/globals.dart';
import 'package:heart/middleware/database.dart';
import 'package:heart/middleware/s3.dart';
import 'package:heart/models/changes.dart';
import 'package:heart/models/errors.dart';
import 'package:heart/models/me.dart';
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
        'the returned cursor for the next page.',
    inputSchema: {
      'type': 'object',
      'properties': {
        'exercise': {'type': 'string', 'description': 'Part of an exercise name, case-insensitive.'},
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
      final sets = await request.workoutsService.getRecordSets(userId: request.userId);
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
        'sessions.',
    inputSchema: {
      'type': 'object',
      'properties': {
        'exerciseId': {'type': 'string', 'description': 'An exercise id from get_workout or get_personal_records.'},
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
      final history =
          await request.workoutsService.getExerciseHistory(
            userId: request.userId,
            exerciseId: id,
            cursor: cursor,
            limit: limit,
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
        'carries achievedAt only once it is). A goal on an exercise names it. Goals on health metrics carry their '
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
    name: 'list_custom_exercises',
    title: 'List custom exercises',
    description:
        'Exercises the user created themselves. Library exercises appear by name inside workouts and templates.',
    run: (request, _) async {
      final library = await request.exerciseService.getExercises(
        request.userId,
        locale: request.locale(request.config.supportedLocales, request.config.defaultLocale),
        owned: true,
      );
      return {
        'exercises': [
          for (final exercise in (library['exercises'] as List? ?? const []).cast<Map>())
            {'name': exercise['name'], 'category': exercise['category'], 'target': exercise['target']},
        ],
      };
    },
  ),
];

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

extension on Map<String, dynamic> {
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
