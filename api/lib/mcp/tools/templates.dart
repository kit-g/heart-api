part of '../tools.dart';

// The template writes (heart-api#184): the first tools that change anything,
// behind `write:templates`. Each one parses its arguments with the input
// class `POST /templates`, `PUT /templates/:id` or `POST /template-folders`
// parses with, and calls the same service method, so a write here is
// validated, limited, id-minted and refused exactly as the app's own is.

final List<McpTool> _templateWrites = [
  McpTool(
    name: 'create_template_folder',
    title: 'Create a template folder',
    description:
        'A folder to file templates in, such as one per program ("4-day upper/lower"). Names are unique per user: '
        'asking for a name the user already has returns that folder (status existing) rather than a second one. '
        'File templates into it with create_template.',
    inputSchema: const {
      'type': 'object',
      'properties': {
        'name': {'type': 'string', 'minLength': 1, 'maxLength': 80},
      },
      'required': ['name'],
      'additionalProperties': false,
    },
    scope: .writeTemplates,
    run: (request, arguments) => _writing(arguments, () async {
      final input = TemplateFolderCreateIn.fromJson({'name': arguments['name']});
      final (folder, created) = await request.templateFolderService.createFolderOrExisting(
        userId: request.userId,
        folder: input.folder,
      );
      return {
        'status': created ? 'created' : 'existing',
        'folder': {'id': folder.id, 'name': folder.name},
      };
    }),
  ),
  McpTool(
    name: 'create_template',
    title: 'Create a template',
    description:
        'A new workout template in the user\'s Heart app: exercises in order, each with its sets. Call it with '
        'preview true first: that checks everything and returns the template as it would be saved, saving nothing. '
        'Show it to the user, and once they agree call again without preview to save it. Exercise ids come from '
        'search_exercises, folder ids from list_template_folders or create_template_folder. A set\'s weightKg, '
        'reps, distanceKm and seconds are what the app fills in when the session starts; target is what the set '
        'aims for. Weights in kg, distances in km, durations in seconds. The app picks the new template up when it '
        'next syncs.',
    inputSchema: _templateSchema(),
    widget: templateWidget,
    scope: .writeTemplates,
    idempotent: false,
    run: (request, arguments) => _writing(arguments, () async {
      final body = arguments.toTemplateBody();
      final TemplateCreateIn(request: template) = TemplateCreateIn.fromJson(body, userId: request.userId);
      final names = await request.checkTemplate(template);
      if (arguments.isPreview) return {'status': 'preview', 'template': template.toMcpPreview(names)};

      final (saved, _) = await request.templatesService.createTemplateOrExisting(
        userId: request.userId,
        body: template,
      );
      return {'status': 'created', 'template': saved.toMcpTemplate()};
    }),
  ),
  McpTool(
    name: 'update_template',
    title: 'Replace a template',
    description:
        'Replaces one of the user\'s templates with what is passed: its exercises and sets are overwritten '
        'whole, so pass every exercise it should keep. A name, note or folderId left out keeps the stored one; '
        'folderId null takes it out of its folder. Call it with preview true first, show the user the result, '
        'and save (no preview) only once they agree. Template ids come from list_templates. A template that is '
        'a session of a program is changed in the app. Units and ids as in create_template.',
    inputSchema: _templateSchema(update: true),
    widget: templateWidget,
    scope: .writeTemplates,
    destructive: true,
    run: (request, arguments) => _writing(arguments, () async {
      final id = arguments['templateId'];
      if (id is! String || !isUuidV7(id)) throw const ToolError('templateId must be an id from list_templates.');
      final Template stored;
      try {
        stored = await request.templatesService.getTemplate(userId: request.userId, templateId: id);
      } on NotFound {
        throw ToolError('No template $id. Use list_templates for valid ids.');
      }
      // a session's exercises are what its program's rules and bases are
      // kept by; replacing them here would leave those pointing at nothing
      if (stored.programId != null) {
        throw const ToolError('This template is a session of a program; programs are changed in the Heart app.');
      }

      final body = arguments.toTemplateBody();
      final TemplateUpdateIn(request: parsed) = TemplateUpdateIn.fromJson({
        'name': ?stored.name,
        // the order is the user's arrangement, which a replace keeps
        'order': stored.order,
        ...body,
      }, userId: request.userId);
      final names = await request.checkTemplate(parsed);
      if (arguments.isPreview) {
        final preview = parsed.toMcpPreview(
          names,
          // what a key left out keeps
          folder: parsed.movesFolder ? null : stored.folder,
          note: parsed.changesNote ? parsed.note : stored.note,
        );
        final folder = preview.remove('folder');
        return {
          'status': 'preview',
          'template': {
            'id': stored.id,
            'folder': ?folder,
            // what a replace keeps of an assigned template is still its author's
            ...stored.quotedIfAssigned(preview),
          },
        };
      }

      final saved = await request.templatesService.updateTemplate(
        userId: request.userId,
        templateId: stored.id,
        body: parsed,
      );
      return {'status': 'updated', 'template': saved.toMcpTemplate()};
    }),
  ),
];

/// Runs a write tool's [body], with the arguments held to the same rules as
/// any body the API reads: nothing health-shaped. A refusal from the input
/// layer, the service or the database comes back as a tool error naming the
/// same code the REST route would, in the tool's own argument names.
Future<Map<String, dynamic>> _writing(
  Map<String, dynamic> arguments,
  Future<Map<String, dynamic>> Function() body,
) async {
  try {
    rejectHealthFields(arguments);
    return await body();
  } on ApiException catch (e) {
    throw ToolError(e.toToolMessage());
  } catch (e) {
    // a constraint the statement did not map, as `apiHandler` reads one
    if (apiExceptionForDbError(e) case final ApiException refused) throw ToolError(refused.toToolMessage());
    rethrow;
  }
}

extension on ApiException {
  /// The refusal as the model reads it: what was wrong, in the tool's argument
  /// names rather than the REST body's, and the code the route answers with.
  String toToolMessage() {
    final reason = switch (this) {
      BadRequest(:final reason) || Forbidden(:final reason) => reason,
      NotFound(code: 'unknown_folder') => 'folderId names no folder of the user\'s',
      NotFound(code: 'unknown_exercise') => 'an exerciseId names no exercise the user has',
      NotFound(type: 'TemplateFolder') => 'folderId names no folder of the user\'s',
      final other => other.toString(),
    };
    final named = reason.replaceAllMapped(_restKeys, (match) => '${match[1]}${_mcpKeys[match[2]]}');
    return '$named ($code).';
  }
}

/// REST body keys inside an input error's path (`exercises[0].sets[1].weight`).
final _restKeys = RegExp(r'([.\]]\.?)(weight|duration|distance|set_type|exercise)\b');

/// What the tools call them.
const _mcpKeys = {
  'weight': 'weightKg',
  'duration': 'seconds',
  'distance': 'distanceKm',
  'set_type': 'type',
  'exercise': 'exerciseId',
};

extension on Request {
  /// Checks what the input layer can't on its own: every exercise is one the
  /// user can use, and the folder, when one is named, is theirs. Answers the
  /// exercises' names and the folder, for a preview to show.
  Future<({Map<String, Map> exercises, TemplateFolder? folder})> checkTemplate(TemplateRequest template) async {
    final (library, folders) = await (
      exerciseService.getExercises(userId),
      switch (template.folderId) {
        null => Future.value(const <TemplateFolder>[]),
        String() => templateFolderService.getFolders(userId: userId),
      },
    ).wait;
    final exercises = <String, Map>{
      for (final row in (library['exercises'] as List? ?? const []).cast<Map>())
        if (row['id'] case final String id) id: row,
    };
    for (final (index, exercise) in template.exercises.indexed) {
      if (!exercises.containsKey(exercise.exerciseId)) {
        throw ToolError('exercises[$index].exerciseId is not an exercise the user has. Use search_exercises for ids.');
      }
    }
    final folder = switch (template.folderId) {
      null => null,
      final String id =>
        folders.where((folder) => folder.id == id).firstOrNull ??
            (throw ToolError('No folder $id. Use list_template_folders or create_template_folder.')),
    };
    return (exercises: exercises, folder: folder);
  }
}

extension on Map<String, dynamic> {
  bool get isPreview => this['preview'] == true;

  /// A tool's template arguments as the REST body the input layer reads:
  /// the tools' unit-named keys (`weightKg`, `seconds`, `distanceKm`) back to
  /// the body's, and only what the tool offers. A key left out stays out, so
  /// a replace keeps what it keeps over REST.
  Map<String, dynamic> toTemplateBody() {
    if (this['preview'] case final Object preview when preview is! bool) {
      throw const ToolError('preview must be true or false.');
    }
    final exercises = switch (this['exercises']) {
      final List list => list,
      _ => throw const ToolError('exercises must be a list of exercises, each with an exerciseId and its sets.'),
    };
    return {
      if (containsKey('name')) 'name': this['name'],
      if (containsKey('note')) 'note': this['note'],
      if (containsKey('folderId')) 'folderId': this['folderId'],
      'exercises': [
        for (final (index, exercise) in exercises.indexed)
          switch (exercise) {
            final Map<String, dynamic> exercise => exercise._toExerciseBody(index),
            _ => throw ToolError('exercises[$index] must be an object with an exerciseId.'),
          },
      ],
    };
  }

  Map<String, dynamic> _toExerciseBody(int index) {
    final at = 'exercises[$index]';
    final id = switch (this['exerciseId']) {
      final String id when id.isNotEmpty => id,
      _ => throw ToolError('$at.exerciseId must be an id from search_exercises.'),
    };
    return {
      'exercise': id,
      if (containsKey('rest')) 'rest': this['rest'],
      if (containsKey('superset')) 'superset': this['superset'],
      'sets': switch (this['sets']) {
        null => const <Object>[],
        final List sets => [
          for (final (setIndex, set) in sets.indexed)
            switch (set) {
              final Map<String, dynamic> set => set._toSetBody('$at.sets[$setIndex]'),
              _ => throw ToolError('$at.sets[$setIndex] must be an object.'),
            },
        ],
        _ => throw ToolError('$at.sets must be a list.'),
      },
    };
  }

  Map<String, dynamic> _toSetBody(String at) {
    return {
      if (containsKey('type')) 'set_type': this['type'],
      if (containsKey('weightKg')) 'weight': this['weightKg'],
      if (containsKey('reps')) 'reps': _whole(this['reps'], at: '$at.reps'),
      if (containsKey('distanceKm')) 'distance': this['distanceKm'],
      if (containsKey('seconds')) 'duration': _whole(this['seconds'], at: '$at.seconds'),
      if (this['target'] case final Object target)
        'target': switch (target) {
          final Map<String, dynamic> target => target._toTargetBody('$at.target'),
          _ => throw ToolError('$at.target must be an object.'),
        },
    };
  }

  /// A set's target in the tools' keys, as the body's: the measures by their
  /// unit names, and `rir`. The program keys (`share`, `of`) stay out: a
  /// template written here belongs to no program.
  Map<String, dynamic> _toTargetBody(String at) {
    const keys = {'reps': 'reps', 'weightKg': 'weight', 'seconds': 'duration', 'distanceKm': 'distance', 'rir': 'rir'};
    return {
      for (final MapEntry(:key, :value) in entries)
        (keys[key] ?? (throw ToolError('$at takes only ${keys.keys.join(', ')}.'))): value,
    };
  }
}

/// Reps and seconds are whole numbers in the database. A model may send 8.0
/// for 8, which is taken as 8; 8.5 is refused here, before the save
/// statement's integer cast would fail on it.
Object? _whole(Object? value, {required String at}) {
  return switch (value) {
    final double n when n == n.truncateToDouble() => n.toInt(),
    final double _ => throw ToolError('$at must be a whole number.'),
    final other => other,
  };
}

/// The input schema both template tools share; [update] adds the template's
/// id and lets the exercises' presence be the whole of what is replaced.
Map<String, dynamic> _templateSchema({bool update = false}) {
  const range = {
    'type': 'object',
    'properties': {
      'min': {'type': 'number', 'minimum': 0},
      'max': {'type': 'number', 'minimum': 0, 'description': 'Leave out for an open top ("8+").'},
      'amrap': {'type': 'boolean', 'description': 'As many as possible, up to max.'},
    },
    'required': ['min'],
    'additionalProperties': false,
  };
  return {
    'type': 'object',
    'properties': {
      if (update) 'templateId': {'type': 'string', 'description': 'An id from list_templates.'},
      'name': {'type': 'string', 'maxLength': 200},
      'note': {'type': 'string', 'maxLength': 1000, 'description': 'A line on what the session is for.'},
      'folderId': {
        'type': ['string', if (update) 'null'],
        'description': 'A folder id from list_template_folders or create_template_folder.',
      },
      'exercises': {
        'type': 'array',
        'description': 'In the order they are done.',
        'items': {
          'type': 'object',
          'properties': {
            'exerciseId': {'type': 'string', 'description': 'An id from search_exercises.'},
            'rest': {'type': 'integer', 'minimum': 0, 'maximum': 1800, 'description': 'Seconds between sets.'},
            'superset': {
              'type': 'integer',
              'minimum': 1,
              'maximum': 50,
              'description': 'Exercises with the same number are done as one superset.',
            },
            'sets': {
              'type': 'array',
              'items': {
                'type': 'object',
                'properties': {
                  'type': {
                    'type': 'string',
                    'enum': [for (final type in SetType.values) type.value],
                  },
                  'weightKg': {'type': 'number'},
                  'reps': {'type': 'integer', 'minimum': 0},
                  'distanceKm': {'type': 'number', 'minimum': 0},
                  'seconds': {'type': 'integer', 'minimum': 0},
                  'target': {
                    'type': 'object',
                    'description': 'What the set aims for: each measure a range, such as reps {min: 6, max: 10}.',
                    'properties': {
                      'reps': range,
                      'weightKg': range,
                      'seconds': range,
                      'distanceKm': range,
                      'rir': {'type': 'number', 'minimum': 0, 'maximum': 10, 'description': 'Reps in reserve.'},
                    },
                    'additionalProperties': false,
                  },
                },
                'additionalProperties': false,
              },
            },
          },
          'required': ['exerciseId'],
          'additionalProperties': false,
        },
      },
      'preview': {
        'type': 'boolean',
        'description': 'Check and show the template without saving it. Do this first.',
      },
    },
    'required': [if (update) 'templateId', 'exercises'],
    'additionalProperties': false,
  };
}

extension on Template {
  /// A saved template as the write tools return it, and the template widget
  /// draws it.
  Map<String, dynamic> toMcpTemplate() {
    return {
      'id': id,
      if (folder case final TemplateFolder folder) 'folder': {'id': folder.id, 'name': folder.name},
      ...quotedIfAssigned({
        // an unnamed template is stored with an empty name
        'name': switch (name) {
          final String name when name.isNotEmpty => name,
          _ => 'Untitled',
        },
        'note': ?note,
        'exercises': [
          for (final exercise in this)
            {
              'exerciseId': exercise.exercise.id,
              'name': exercise.exercise.name,
              'category': exercise.exercise.category.value,
              'rest': ?exercise.rest,
              'superset': ?exercise.superset,
              'sets': [
                for (final set in exercise)
                  (
                    weight: set.weight,
                    reps: set.reps,
                    distance: set.distance,
                    duration: set.duration,
                  ).toMcpTemplateSet(type: set.setType, target: set.target),
              ],
            },
        ],
      }),
    };
  }
}

extension on TemplateRequest {
  /// What [toMcpTemplate] would return once this is saved, from the checked
  /// request and [checked]'s names. [folder] and [note] stand in for what a
  /// replace keeps when its body leaves them out.
  Map<String, dynamic> toMcpPreview(
    ({Map<String, Map> exercises, TemplateFolder? folder}) checked, {
    TemplateFolder? folder,
    String? note,
  }) {
    return {
      if (checked.folder ?? folder case final TemplateFolder filed) 'folder': {'id': filed.id, 'name': filed.name},
      'name': name ?? 'Untitled',
      'note': ?(note ?? this.note),
      'exercises': [
        for (final exercise in exercises)
          {
            'exerciseId': exercise.exerciseId,
            'name': ?checked.exercises[exercise.exerciseId]?['name'],
            'category': ?checked.exercises[exercise.exerciseId]?['category'],
            'rest': ?exercise.rest,
            'superset': ?exercise.superset,
            'sets': [
              for (final set in exercise.sets)
                (
                  weight: set.weight,
                  reps: set.reps?.toInt(),
                  distance: set.distance,
                  duration: set.duration,
                ).toMcpTemplateSet(type: set.setType ?? .normal, target: set.target),
            ],
          },
      ],
    };
  }
}

extension on _Measures {
  /// A template set as the tools show it: its [type] when it isn't a normal
  /// set, these measures (what the app prefills), and its [target] in the
  /// tools' unit names.
  Map<String, dynamic> toMcpTemplateSet({required SetType type, required SetTarget? target}) {
    return {
      'type': ?(type == .normal ? null : type.value),
      ...toMcp(),
      if (target case final SetTarget target when !target.isEmpty) 'target': target.toMap().toMcpUnits(),
    };
  }
}
