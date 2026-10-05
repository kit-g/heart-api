import 'package:heart/core/request.dart';
import 'package:heart/globals/config.dart';
import 'package:heart/globals/globals.dart';
import 'package:heart/middleware/database.dart';
import 'package:heart/middleware/s3.dart';
import 'package:heart/models/errors.dart';
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
      final (limit, cursor) = _page(arguments, defaultLimit: 20, maxLimit: 50);
      final page = await request.workoutsService.getWorkouts(
        userId: request.userId,
        targetUserId: request.userId,
        limit: limit,
        cursor: cursor,
        imageUrl: request.config.cdnAssetUrl,
      );
      return {
        'workouts': page.items.map(_workoutSummary).toList(),
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
        return _workoutDetail(workout);
      } on NotFound {
        throw ToolError('No workout $id. Use list_workouts for valid ids.');
      }
    },
  ),
  McpTool(
    name: 'list_templates',
    title: 'List templates',
    description: "The user's workout templates in their own order, with each template's exercises and set count.",
    inputSchema: _pageSchema(maxLimit: 100),
    run: (request, arguments) async {
      final (limit, cursor) = _page(arguments, defaultLimit: 50, maxLimit: 100);
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
        "The user's goals: what is measured, the targets and deadlines, and which stages are achieved. Goals on "
        'health metrics carry their definition only; their progress lives on the phone.',
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
      return {'goals': goals.map((goal) => goal.toMap()).toList()};
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

(int, String?) _page(Map<String, dynamic> arguments, {required int defaultLimit, required int maxLimit}) {
  final limit = switch (arguments['limit']) {
    final int n => n.clamp(1, maxLimit),
    null => defaultLimit,
    _ => throw const ToolError('limit must be a whole number.'),
  };
  final cursor = switch (arguments['cursor']) {
    final String c when c.isNotEmpty => c,
    null => null,
    _ => throw const ToolError('cursor must be the string returned by the previous page.'),
  };
  return (limit, cursor);
}

Map<String, dynamic> _workoutSummary(Workout workout) {
  return {
    'id': workout.id,
    'name': ?workout.name,
    'start': workout.start.toUtc().toIso8601String(),
    'minutes': ?workout.end?.difference(workout.start).inMinutes,
    'exercises': [
      for (final exercise in workout)
        {
          'name': exercise.exercise.name,
          'completedSets': exercise.where((set) => set.isCompleted).length,
          'best': ?switch (exercise.best) {
            final ExerciseSet set => _set(set),
            null => null,
          },
        },
    ],
  };
}

Map<String, dynamic> _workoutDetail(Workout workout) {
  return {
    'id': workout.id,
    'name': ?workout.name,
    'start': workout.start.toUtc().toIso8601String(),
    'end': ?workout.end?.toUtc().toIso8601String(),
    'note': ?workout.note,
    'caloriesEstimate': ?workout.calories?.round(),
    'exercises': [
      for (final exercise in workout)
        {
          'name': exercise.exercise.name,
          'note': ?exercise.note,
          'sets': [for (final set in exercise) _set(set)],
        },
    ],
  };
}

Map<String, dynamic> _set(ExerciseSet set) {
  return {
    'type': ?(set.setType == .normal ? null : set.setType.value),
    'weightKg': ?set.weight,
    'reps': ?set.reps,
    'distanceKm': ?set.distance,
    'seconds': ?set.duration,
    'rpe': ?set.rpe,
    if (!set.isCompleted) 'completed': false,
  };
}
