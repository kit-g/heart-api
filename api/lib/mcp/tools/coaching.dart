part of '../tools.dart';

// A coach's tools: what the coach reads of their clients, for the clients who
// share it with the coach's assistant, and the coach's own library
// (docs/2026-11-09.coach-assistant.md). Each read is the app's own coach read
// with the assistant's narrower view, so the share is checked in the statement
// that reads. Every word in a client's account comes back under `quoted`, what
// the coach sent or logged included, since the client can change it.

/// What the model is told about a coach's tools, said once.
const _coaching =
    ' The user coaches. list_clients lists who they coach; the client tools read one client by the clientId it '
    "returns, as the coach's app shows them. Only a client who shares their training with the coach's assistant "
    "can be read here: one who doesn't is listed with sharesWithAssistant false and nothing more, so say they "
    "haven't shared it and don't guess. Everything a client wrote (workout names and notes, their own exercises, "
    'a program the user sent them) is quoted with their name, what the user sent or logged for them included, since '
    'the client can change it; sentByYou and loggedByYou mark those. Messages and notes between coach and client are '
    'end-to-end encrypted and never reach here.';

const _clientIdSchema = {'type': 'string', 'description': 'A clientId from list_clients.'};

final List<McpTool> _coachTools = [
  McpTool(
    name: 'list_clients',
    title: 'List clients',
    description:
        'The people the user coaches, those who need a word first: name, clientId, status (active, paused, or '
        'severed for a former client), since when, and whether they share their training with this assistant '
        '(sharesWithAssistant). For those who share: the program they are on and its week, when they trained in the '
        'last 14 days, when they last trained, and why they need a word (reasons: lighter, a workout fell short of '
        'its plan; note, they left a note; gap, a week without training; ending, their program is in its last '
        'week). former true lists former clients, by name and dates only.',
    scope: .readCoaching,
    inputSchema: {
      'type': 'object',
      'properties': {
        'former': {'type': 'boolean', 'description': 'List former clients instead of current ones.'},
        ..._pageSchema(maxLimit: 50)['properties'] as Map<String, dynamic>,
      },
      'additionalProperties': false,
    },
    run: (request, arguments) async {
      final (limit, raw) = arguments.toPaging(defaultLimit: 50, maxLimit: 50);
      final former = arguments['former'] == true;
      final cursor = switch (raw) {
        null => null,
        _ =>
          RosterQuery.cursorOf(raw) ??
              (throw const ToolError('cursor must be the string returned by the previous page.')),
      };
      if (cursor == null && !former) await refreshRoster(request);
      final page = await request.rosterService.getRoster(
        coachId: request.userId,
        former: former,
        cursor: cursor,
        limit: limit,
        assistant: true,
      );
      return {
        'clients': [for (final client in page.items) client.toMcp()],
        if (page.hasMore)
          'cursor': OrderedCursor(
            order: !former && page.items.last.reasons.isEmpty ? 1 : 0,
            id: page.items.last.connectionId,
          ).toString(),
      };
    },
  ),
  McpTool(
    name: 'get_coach_feed',
    title: 'Coach feed',
    description:
        "What the user's clients did lately, newest first: a workout finished, a session skipped, a program in its "
        'last week. Only clients who share their training with this assistant. Each names the client and their '
        'clientId; get_client_workout reads a workout in full by its id.',
    scope: .readCoaching,
    inputSchema: _pageSchema(maxLimit: 50),
    run: (request, arguments) async {
      final (limit, raw) = arguments.toPaging(defaultLimit: 30, maxLimit: 50);
      final cursor = switch (raw) {
        null => null,
        _ =>
          CoachFeedQuery.cursorOf(raw) ??
              (throw const ToolError('cursor must be the string returned by the previous page.')),
      };
      if (cursor == null) await refreshRoster(request);
      final page = await request.rosterService.getCoachFeed(
        coachId: request.userId,
        cursor: cursor,
        limit: limit,
        assistant: true,
      );
      return {
        'items': [
          for (final item in page.items)
            {
              'kind': item.kind,
              'id': item.id,
              'clientId': item.studentId,
              'client': ?item.name,
              'at': item.at.toUtc().toIso8601String(),
              if (item.title case final String title) ..._quoted({'title': title}, by: item.name),
            },
        ],
        if (page.hasMore) 'cursor': page.items.last.cursor,
      };
    },
  ),
  McpTool(
    name: 'list_client_workouts',
    title: "List a client's workouts",
    description:
        "One client's workouts, newest first, as summaries: name, date, duration, and per exercise the number of "
        'completed sets and the best set. Only what their coach can read: from when coaching began (earlier only '
        'if they share their history), nothing they hid, nothing from a pause. loggedByYou marks one the user '
        'logged for them, still quoted, as the client can change it. Use get_client_workout for every set of one.',
    scope: .readCoaching,
    inputSchema: {
      'type': 'object',
      'properties': {'clientId': _clientIdSchema, ..._pageSchema(maxLimit: 50)['properties'] as Map<String, dynamic>},
      'required': ['clientId'],
      'additionalProperties': false,
    },
    run: (request, arguments) async {
      final clientId = arguments.clientId(request);
      final (limit, cursor) = arguments.toPaging(defaultLimit: 20, maxLimit: 50);
      if (cursor != null && !isUuidV7(cursor)) {
        throw const ToolError('cursor must be the string returned by the previous page.');
      }
      final page = await _asClient(
        clientId,
        () => request.workoutsService.getWorkouts(
          userId: request.userId,
          targetUserId: clientId,
          limit: limit,
          cursor: cursor,
          imageUrl: request.config.cdnAssetUrl,
          assistant: true,
        ),
      );
      final client = await request.client(clientId, lifts: .own);
      return {
        'client': ?client.name,
        'workouts': [
          for (final workout in page.items)
            {
              ...workout.toMcpSummary(
                coached: client.exercises,
                quote: client.quote,
              ),
              if (workout.loggedBy == request.userId) 'loggedByYou': true,
            },
        ],
        if (page.hasMore) 'cursor': page.items.last.id,
      };
    },
  ),
  McpTool(
    name: 'get_client_workout',
    title: "Get a client's workout",
    description:
        "One of a client's workouts in full: every exercise and set, with set types, RPE and notes, and the target "
        'a set aimed for when it came from a template or program (as get_workout gives them). A target is the plan, '
        'not what was done.',
    scope: .readCoaching,
    inputSchema: {
      'type': 'object',
      'properties': {
        'clientId': _clientIdSchema,
        'workoutId': {'type': 'string', 'description': 'An id from list_client_workouts or get_coach_feed.'},
      },
      'required': ['clientId', 'workoutId'],
      'additionalProperties': false,
    },
    run: (request, arguments) async {
      final clientId = arguments.clientId(request);
      final id = arguments['workoutId'];
      if (id is! String || !isUuidV7(id)) {
        throw const ToolError('workoutId must be an id from list_client_workouts or get_coach_feed.');
      }
      final Workout workout;
      try {
        workout = await _asClient(
          clientId,
          () => request.workoutsService.getTargetWorkout(
            requesterId: request.userId,
            targetUserId: clientId,
            workoutId: id,
            imageUrl: request.config.cdnAssetUrl,
            assistant: true,
          ),
        );
      } on NotFound {
        throw ToolError('No workout $id of this client that you can read. Use list_client_workouts for valid ids.');
      }
      final targets = workout.any((exercise) => exercise.any((set) => set.target?.of != null));
      final client = await request.client(clientId, lifts: targets ? .all : .own);
      return {
        ...workout.toMcpDetail(
          names: client.names,
          coached: client.exercises,
          quote: client.quote,
        ),
        if (workout.loggedBy == request.userId) 'loggedByYou': true,
      };
    },
  ),
  McpTool(
    name: 'list_client_programs',
    title: "List a client's programs",
    description:
        'The programs the user sent one client, as the client holds them: name, whether archived, and how many '
        'sessions. Empty for a client who does not share their training with this assistant.',
    scope: .readCoaching,
    inputSchema: {
      'type': 'object',
      'properties': {'clientId': _clientIdSchema},
      'required': ['clientId'],
      'additionalProperties': false,
    },
    run: (request, arguments) async {
      final clientId = arguments.clientId(request);
      final copies = await request.programChangeService.getCopies(
        coachId: request.userId,
        studentId: clientId,
        assistant: true,
      );
      if (copies.isEmpty) return {'programs': const <Object>[]};
      final client = await request.client(clientId);
      return {
        'client': ?client.name,
        'programs': [
          for (final program in copies)
            {
              'id': program.id,
              ..._quoted({'name': program.name}, by: client.name),
              'archived': program.archived,
              'sessions': program.sessions.length,
            },
        ],
      };
    },
  ),
  McpTool(
    name: 'get_client_program',
    title: "Get a client's program",
    description:
        'One program the user sent a client, as the client holds it now: its sessions in order with which are done '
        'in the open cycle, and where the client stands: the program week, the next session, whether it is paused or '
        'finished, and workouts this week against the weekly target. Worked out from what the coach can read, so a '
        'workout they hid leaves its session undone here. Every session is quoted as the client\'s, as they can '
        'change it; sentByYou marks one the user sent or wrote into, and get_client_program_changes says who '
        'changed what.',
    scope: .readCoaching,
    inputSchema: {
      'type': 'object',
      'properties': {
        'clientId': _clientIdSchema,
        'programId': {'type': 'string', 'description': 'An id from list_client_programs.'},
      },
      'required': ['clientId', 'programId'],
      'additionalProperties': false,
    },
    run: (request, arguments) async {
      final (clientId, programId) = (arguments.clientId(request), arguments.programId());
      final CoachProgramView view;
      try {
        view = await _asClient(
          clientId,
          () => copies.copyView(request, student: clientId, programId: programId, assistant: true),
        );
      } on NotFound {
        throw ToolError('No program $programId of this client. Use list_client_programs for valid ids.');
      }
      final client = await request.client(clientId, lifts: .own);
      final done = {...?(view.position['done'] as List?)};
      final program = view.program;
      return {
        'client': ?client.name,
        'id': program.id,
        ..._quoted({'name': program.name, 'note': ?program.note}, by: client.name),
        'perWeek': ?program.perWeek,
        'weeks': ?program.weeks,
        'archived': program.archived,
        'position': {...view.position}
          ..remove('done')
          ..remove('remaining'),
        'sessions': [
          for (final session in view.sessions)
            {
              'id': session.id,
              'done': done.contains(session.id),
              if (session.assignedBy?.id == request.userId) 'sentByYou': true,
              ..._quoted(
                {
                  'name': session.name ?? 'Untitled',
                  'note': ?session.note,
                  'exercises': [
                    for (final exercise in session) client.exercises.name(exercise.exercise.id, exercise.exercise.name),
                  ],
                },
                // another coach's session is theirs; the rest the client holds
                by: switch (session.assignedBy) {
                  final Profile by when by.id != request.userId => by.quotedName,
                  _ => client.name,
                },
              ),
            },
        ],
      };
    },
  ),
  McpTool(
    name: 'get_client_program_changes',
    title: "A client's program changes",
    description:
        'What changed in a program the user sent a client, oldest first: who made each change (you, the user; or '
        'the client), what kind (edit, create, delete, revert, library_update: the user sent a new version), which '
        'session (sessionId; none for the program itself), and how it stood before and after, quoted as the '
        "client's whoever made the change, since it is their copy. Pass cursor back while one is returned.",
    scope: .readCoaching,
    inputSchema: {
      'type': 'object',
      'properties': {
        'clientId': _clientIdSchema,
        'programId': {'type': 'string', 'description': 'An id from list_client_programs.'},
        'cursor': {'type': 'string', 'description': 'The cursor from the previous page.'},
      },
      'required': ['clientId', 'programId'],
      'additionalProperties': false,
    },
    run: (request, arguments) async {
      final (clientId, programId) = (arguments.clientId(request), arguments.programId());
      final since = switch (arguments['cursor']) {
        null => null,
        final String cursor when cursor.isNotEmpty => cursor,
        _ => throw const ToolError('cursor must be the string returned by the previous page.'),
      };
      final Page<ProgramChange> changes;
      try {
        changes = await _asClient(
          clientId,
          () => copies.copyChanges(request, student: clientId, programId: programId, since: since, assistant: true),
        );
      } on NotFound {
        throw ToolError('No program $programId of this client. Use list_client_programs for valid ids.');
      } on BadRequest {
        throw const ToolError('cursor must be the string returned by the previous page, or none to start over.');
      }
      final client = await request.client(clientId);
      return {
        'client': ?client.name,
        'changes': [
          for (final change in changes.items)
            {
              'at': change.at.toUtc().toIso8601String(),
              'by': change.actorId == request.userId ? 'you' : 'client',
              'kind': change.kind,
              'sessionId': ?change.sessionId,
              // a snapshot is the whole copy as it stood, the client's words in it
              ..._quoted({'before': ?change.before, 'after': ?change.after}, by: client.name),
            },
        ],
        if (changes.hasMore) 'cursor': changes.items.last.cursor,
      };
    },
  ),
  McpTool(
    name: 'list_client_goals',
    title: "List a client's goals",
    description:
        "One client's goals, when they share their goals with the user as well as their training with this "
        'assistant: what is measured, the targets and deadlines, and which stages are achieved, as list_goals gives '
        'them. Goals on health metrics carry their definition only.',
    scope: .readCoaching,
    inputSchema: {
      'type': 'object',
      'properties': {
        'clientId': _clientIdSchema,
        'archived': {'type': 'boolean', 'description': 'List archived goals instead of active ones.'},
      },
      'required': ['clientId'],
      'additionalProperties': false,
    },
    run: (request, arguments) async {
      final clientId = arguments.clientId(request);
      final goals = await _asClient(
        clientId,
        () => request.goalService.getTargetUserGoals(
          requesterId: request.userId,
          targetUserId: clientId,
          archived: arguments['archived'] == true,
          assistant: true,
        ),
        what: 'their goals',
      );
      final client = await request.client(clientId, lifts: goals.any((goal) => goal.exerciseId != null) ? .all : .none);
      return {
        'client': ?client.name,
        'goals': [
          for (final goal in goals) {...goal.toMap(), 'exerciseName': ?client.names[goal.exerciseId]},
        ],
      };
    },
  ),
  McpTool(
    name: 'list_my_library',
    title: 'List my coaching library',
    description:
        "The programs in the user's own coaching library, which they send to clients: name, version and when it "
        "last changed, newest first. These are the user's own, not Heart's library (list_library_programs).",
    scope: .readCoaching,
    inputSchema: _pageSchema(maxLimit: 50),
    run: (request, arguments) async {
      final (limit, cursor) = arguments.toPaging(defaultLimit: 30, maxLimit: 50);
      if (cursor != null && !isUuidV7(cursor)) {
        throw const ToolError('cursor must be the string returned by the previous page.');
      }
      final page = await request.coachLibraryService.getCoachPrograms(
        coachId: request.userId,
        cursor: cursor,
        limit: limit,
      );
      return {
        'programs': [
          for (final program in page.items)
            {
              'id': program.id,
              'name': program.name,
              'version': program.version,
              'updatedAt': program.updatedAt.toUtc().toIso8601String(),
            },
        ],
        if (page.hasMore) 'cursor': page.items.last.id,
      };
    },
  ),
  McpTool(
    name: 'get_my_library_program',
    title: 'Get a program from my coaching library',
    description:
        "One program from the user's coaching library, its current version in full: sessions, exercises and sets "
        'with their targets, and its growth rules, as the user saved it, each exercise by its name.',
    scope: .readCoaching,
    inputSchema: {
      'type': 'object',
      'properties': {
        'programId': {'type': 'string', 'description': 'An id from list_my_library.'},
      },
      'required': ['programId'],
      'additionalProperties': false,
    },
    run: (request, arguments) async {
      final id = arguments['programId'];
      if (id is! String || !isUuidV7(id)) throw const ToolError('programId must be an id from list_my_library.');
      final CoachProgram program;
      try {
        program = await request.coachLibraryService.getCoachProgram(coachId: request.userId, id: id);
      } on NotFound {
        throw ToolError('No program $id in your library. Use list_my_library for valid ids.');
      }
      final (library, coached) = await (
        request.exerciseService.getExercises(request.userId),
        request.coachedExercises(),
      ).wait;
      return {
        ...?(program.body.namedBy(library.toExerciseNames(coached)) as Map<String, dynamic>?),
        // the server's own say, over anything the body carries
        'id': program.id,
        'name': program.name,
        'version': program.version,
        'updatedAt': program.updatedAt.toUtc().toIso8601String(),
      };
    },
  ),
];

/// [read], with a refusal said as the model can act on it: not one of the user's
/// clients, or one who doesn't share [what] with this assistant.
Future<T> _asClient<T>(String clientId, Future<T> Function() read, {String what = 'their training'}) async {
  try {
    return await read();
  } on Forbidden {
    throw ToolError(
      "You can't read $what here: $clientId isn't a client who shares it with this assistant. list_clients says "
      'who does.',
    );
  }
}

/// Which of a client's exercises a tool names: none, their own, or every one they
/// can use, for a target or goal that points at one.
enum _Lifts { none, own, all }

/// A client, as their words are quoted: their name, their own exercises named as
/// theirs or as the coach's who sent them, and with [_Lifts.all] every exercise's
/// name by id.
typedef _Client = ({String? name, _Coached exercises, Map<String, Object> names});

extension on _Client {
  /// A workout's words, quoted as the client's, whoever logged it: the client can
  /// change it, and who logged one is the client's and that coach's to know
  /// (heart-api#405), so another coach's reads as the client's own.
  _Quote get quote =>
      (text) => _quoted(text, by: name);
}

extension on Request {
  /// Read only once a read of theirs was allowed, so nothing here says more of
  /// someone than that read did.
  Future<_Client> client(String clientId, {_Lifts lifts = .none}) async {
    final empty = Future.value(const <String, dynamic>{});
    final (profile, exercises, sentBy) = await (
      profileService.getProfile(clientId),
      switch (lifts) {
        .none => empty,
        .own => exerciseService.getExercises(clientId, owned: true),
        .all => exerciseService.getExercises(clientId),
      },
      switch (lifts) {
        .none => Future.value(const <String, String?>{}),
        _ => exerciseService.getCoachedExercises(clientId),
      },
    ).wait;
    final name = profile?.displayName;
    final coached = _Coached({
      for (final row in exercises['exercises'] as List? ?? const [])
        if (row case {'id': final String id} when lifts == .own || row['own'] == true)
          // one a coach sent is theirs, as it reads to the client
          id: sentBy.containsKey(id) ? sentBy[id] ?? _anotherAccount : name,
    });
    return (
      name: name,
      exercises: coached,
      names: lifts == .all ? exercises.toExerciseNames(coached) : const <String, Object>{},
    );
  }
}

extension on Map<String, dynamic> {
  String clientId(Request request) {
    return switch (this['clientId']) {
      final String id when id == request.userId => throw const ToolError(
        "That is the user's own id, not a client's: list_workouts, get_workout and list_goals read their own.",
      ),
      final String id when id.isNotEmpty && id.length <= 128 => id,
      _ => throw const ToolError('clientId must be a clientId from list_clients.'),
    };
  }

  String programId() {
    return switch (this['programId']) {
      final String id when isUuidV7(id) => id,
      _ => throw const ToolError('programId must be an id from list_client_programs.'),
    };
  }
}

extension on ClientSummary {
  Map<String, dynamic> toMcp() {
    return {
      'clientId': studentId,
      'name': ?name,
      'status': status,
      'since': ?acceptedAt?.toUtc().toIso8601String(),
      'sharesWithAssistant': assistant,
      if (programName case final String program)
        'program': {
          ..._quoted({'name': program}, by: name),
          'week': ?programWeek,
          'weeks': ?programWeeks,
        },
      if (recent.isNotEmpty) 'recent': [for (final at in recent) at.toUtc().toIso8601String()],
      'lastTrainedAt': ?lastTrainedAt?.toUtc().toIso8601String(),
      if (reasons.isNotEmpty) 'reasons': reasons,
    };
  }
}

extension on Object? {
  /// A library program's body with each exercise id in it, as a value or a key,
  /// replaced by the exercise's name in [names]. A key keeps its id where the
  /// name is quoted.
  Object? namedBy(Map<String, Object> names) {
    return switch (this) {
      final Map<dynamic, dynamic> map => <String, dynamic>{
        for (final MapEntry(:key, value: Object? value) in map.entries)
          switch (names[key]) {
            final String name => name,
            _ => '$key',
          }: value.namedBy(
            names,
          ),
      },
      final List<dynamic> list => [for (final Object? value in list) value.namedBy(names)],
      final String id => names[id] ?? id,
      final other => other,
    };
  }
}
