part of 'inputs.dart';

/// `POST /programs` — the program and its sessions:
/// `{id?, name, note?, source?, perWeek?, days?, weeks?, rules?, constraint?, sessions: [template, ...]}`.
///
/// Each session is a template body, as `POST /templates` takes one, and becomes
/// a template of the program. Starting a library program is this call: the
/// device makes the copy and sends it whole. A session whose `id` is one of the
/// caller's templates already, such as a folder's, joins as it is, at its
/// `order` (heart-api#244).
class ProgramCreateIn {
  /// More sessions than any plan has, few enough to keep one create cheap.
  static const maxSessions = 50;

  final Program program;
  final List<TemplateRequest> sessions;

  const new _({required this.program, required this.sessions});

  static Future<ProgramCreateIn> fromRequest(Request req) async {
    final json = await req.json();
    final sessions = switch (json['sessions']) {
      null => const <Object?>[],
      final List l when l.length <= maxSessions => l,
      final List _ => throw const BadRequest(reason: 'a program has at most $maxSessions sessions'),
      _ => throw const BadRequest(reason: 'sessions must be an array'),
    };
    return ProgramCreateIn._(
      program: Program(
        id: json.uuidV7OrNull(),
        name: json.programName(),
        note: json.templateNote(),
        source: json.programKey('source'),
        perWeek: json.programCount('perWeek', max: 28),
        days: json.programDays(),
        weeks: json.programCount('weeks', max: 104),
        rules: json.programRules(),
        constraint: json.programKey('constraint'),
        deload: json.programDeload(),
        phases: json.programPhases(),
        tests: json.programTests(),
      ),
      sessions: [
        for (final (index, session) in sessions.indexed)
          switch (session) {
            final Map m => _session(req.userId, m.cast<String, dynamic>()),
            _ => throw BadRequest(reason: 'sessions[$index] must be an object'),
          },
      ],
    );
  }
}

/// `PUT /programs/:programId` — a full replace of the program's own fields.
/// `source` is where it came from and never changes; sessions change through
/// their templates.
class ProgramUpdateIn {
  final Program program;

  const new _(this.program);

  static Future<ProgramUpdateIn> fromRequest(Request req) async {
    final json = await req.json();
    return ProgramUpdateIn._(
      Program(
        name: json.programName(),
        note: json.templateNote(),
        perWeek: json.programCount('perWeek', max: 28),
        days: json.programDays(),
        weeks: json.programCount('weeks', max: 104),
        rules: json.programRules(),
        constraint: json.programKey('constraint'),
        deload: json.programDeload(),
        phases: json.programPhases(),
        tests: json.programTests(),
        archived: json.boolean('archived'),
      ),
    );
  }
}

/// `DELETE /programs/:programId?keepTemplates=` — by default the sessions go
/// with the program; `keepTemplates=true` leaves them as plain templates.
class ProgramDeleteQuery {
  final bool keepTemplates;

  const new _({required this.keepTemplates});

  static ProgramDeleteQuery fromRequest(Request req) {
    return ProgramDeleteQuery._(keepTemplates: req.url.queryParameters.boolean('keepTemplates'));
  }
}

TemplateRequest _session(String userId, Map<String, dynamic> json) {
  return TemplateRequest(
    userId: userId,
    id: json.uuidV7OrNull(),
    name: json.templateName(),
    order: json.templateOrder(),
    folderId: json.folderIdOrNull(),
    joined: json.dateOrNull('joined'),
    note: json.templateNote(),
    exercises: json.templateExercises(),
  );
}

extension on Map<String, dynamic> {
  String programName() {
    return switch (this['name']) {
      final String n when n.trim().isNotEmpty && n.trim().length <= 100 => n.trim(),
      _ => throw const BadRequest(reason: 'name must be a string of 1 to 100 chars'),
    };
  }

  /// A content id: a library program, a constraint. Which ones exist is the
  /// library's business, so only the spelling is checked.
  String? programKey(String field) {
    return switch (this[field]) {
      null => null,
      final String key when _contentKey.hasMatch(key) => key,
      _ => throw BadRequest(code: 'invalid_key', reason: '$field must be a snake_case key of at most 64 characters'),
    };
  }

  int? programCount(String field, {required int max}) {
    return switch (this[field]) {
      null => null,
      final int n when n >= 1 && n <= max => n,
      _ => throw BadRequest(reason: '$field must be a whole number from 1 to $max'),
    };
  }

  Set<int> programDays() {
    return switch (this['days']) {
      null => const {},
      final List days when days.every((day) => day is int && day >= 1 && day <= 7) => {...days.cast<int>()},
      _ => throw const BadRequest(reason: 'days must be an array of ISO weekdays, 1 Monday to 7 Sunday'),
    };
  }

  /// A lighter week every N cycles: `{every, load?, volume?}`.
  Deload? programDeload() {
    return switch (this['deload']) {
      null => null,
      final Map deload when deload.keys.every(const {'every', 'load', 'volume'}.contains) => _deload(deload),
      _ => throw const BadRequest(code: 'invalid_deload', reason: 'deload must be {every, load?, volume?}'),
    };
  }

  /// Blocks in order, each with its own sessions; only the last may run on.
  List<ProgramPhase> programPhases() {
    final raw = switch (this['phases']) {
      null => const <Object?>[],
      final List phases when phases.length <= 20 => phases,
      _ => throw const BadRequest(code: 'invalid_phase', reason: 'phases must be a list of at most 20'),
    };
    final phases = [
      for (final (index, phase) in raw.indexed)
        switch (phase) {
          final Map phase => _phase(index, phase),
          _ => throw BadRequest(code: 'invalid_phase', reason: 'phases[$index] must be an object'),
        },
    ];
    for (final (index, phase) in phases.indexed) {
      if (phase.cycles == null && index != phases.length - 1) {
        throw BadRequest(code: 'invalid_phase', reason: 'phases[$index] runs on, so it must be the last');
      }
    }
    return phases;
  }

  /// Test sessions by template id, each `{share?}`.
  Map<String, ProgramTest> programTests() {
    final raw = switch (this['tests']) {
      null => const <String, Object?>{},
      final Map tests => tests,
      _ => throw const BadRequest(code: 'invalid_test', reason: 'tests must be an object of session id to test'),
    };
    return {
      for (final MapEntry(:key, :value) in raw.entries)
        switch (key) {
          final String id when isUuidV7(id) => id,
          _ => throw BadRequest(code: 'invalid_test', reason: 'tests keys are session ids; $key is not one'),
        }: switch (value) {
          final Map test => _test(key, test),
          _ => throw BadRequest(code: 'invalid_test', reason: 'tests.$key must be an object'),
        },
    };
  }

  /// A rule per exercise id, read strictly: a newer kind is a 400 here until
  /// the server knows it, though a build that predates it carries it untouched.
  Map<String, GrowthRule> programRules() {
    final rules = switch (this['rules']) {
      null => const <String, dynamic>{},
      final Map m => m,
      _ => throw const BadRequest(code: 'invalid_rule', reason: 'rules must be an object of exercise id to rule'),
    };
    return {
      for (final MapEntry(:key, :value) in rules.entries)
        switch (key) {
          final String id when isUuidV7(id) => id,
          _ => throw BadRequest(code: 'invalid_rule', reason: 'rules keys are exercise or slot ids; $key is not one'),
        }: switch (value) {
          final Map rule => _rule(key, rule),
          _ => throw BadRequest(code: 'invalid_rule', reason: 'rules.$key must be an object'),
        },
    };
  }
}

ProgramPhase _phase(int index, Map json) {
  final ProgramPhase phase;
  try {
    phase = ProgramPhase.fromJson(json);
  } on ArgumentError catch (e) {
    throw BadRequest(code: 'invalid_phase', reason: 'phases[$index].${e.name}: ${e.message}');
  }
  if (!phase.sessions.every(isUuidV7) || phase.sessions.length > ProgramCreateIn.maxSessions) {
    throw BadRequest(code: 'invalid_phase', reason: 'phases[$index].sessions are session ids, at most 50');
  }
  return phase;
}

ProgramTest _test(Object? sessionId, Map json) {
  try {
    return ProgramTest.fromJson(json);
  } on ArgumentError catch (e) {
    throw BadRequest(code: 'invalid_test', reason: 'tests.$sessionId.${e.name}: ${e.message}');
  }
}

Deload _deload(Map json) {
  try {
    return Deload.fromJson(json);
  } on ArgumentError catch (e) {
    throw BadRequest(code: 'invalid_deload', reason: 'deload.${e.name}: ${e.message}');
  }
}

GrowthRule _rule(String exerciseId, Map json) {
  final GrowthRule rule;
  try {
    rule = GrowthRule.fromJson(json);
  } on ArgumentError catch (e) {
    throw BadRequest(code: 'invalid_rule', reason: 'rules.$exerciseId: ${e.name} ${e.message}');
  }
  // a client carries fields it doesn't know; the server knows every field it
  // accepts, so one it doesn't is a mistake, not a newer vocabulary
  if (rule.extra.isNotEmpty) {
    throw BadRequest(code: 'invalid_rule', reason: 'rules.$exerciseId: unknown ${rule.extra.keys.join(', ')}');
  }
  // and inside the miss rule and the AMRAP table, which read only what they know
  final unknown = {
    if (json['miss'] case final Map miss)
      ...miss.keys.where((key) => !_missKeys.contains(key)).map((key) => 'miss.$key'),
    if (json['amrap'] case final List amrap)
      for (final (at, row) in amrap.indexed)
        if (row case final Map row)
          ...row.keys.where((key) => !_amrapKeys.contains(key)).map((key) => 'amrap[$at].$key'),
    if (json['stages'] case final List stages)
      for (final (at, stage) in stages.indexed)
        if (stage case final Map stage)
          ...stage.keys.where((key) => !_stageKeys.contains(key)).map((key) => 'stages[$at].$key'),
  };
  if (unknown.isNotEmpty) {
    throw BadRequest(code: 'invalid_rule', reason: 'rules.$exerciseId: unknown ${unknown.join(', ')}');
  }
  if (rule case Ladder(:final rungs) when !rungs.every(isUuidV7)) {
    throw BadRequest(code: 'invalid_rule', reason: 'rules.$exerciseId: a ladder\'s rungs are exercise ids');
  }
  return rule;
}

const _missKeys = {'when', 'floor', 'after', 'cut'};
const _amrapKeys = {'reps', 'step'};
const _stageKeys = {'sets', 'reps', 'amrap'};

/// `POST /programs/:programId/actions` —
/// `{id?, kind, week?, from?, to?, exercise?, slot?, stage?, workoutId?, at}`.
/// Only a replay names a week; only an advance names the exercises it moved
/// from and to; only a stage names its exercise, slot and stage; only those
/// two name the workout that caused them.
class ProgramActionIn {
  final ProgramAction action;

  const new _(this.action);

  static Future<ProgramActionIn> fromRequest(Request req) async {
    final json = await req.json();
    final kind = json.parsed('kind', ProgramActionKind.fromString);
    final week = switch ((kind, json['week'])) {
      (.replay, final int week) when week >= 1 && week <= 104 => week,
      (.replay, _) => throw const BadRequest(reason: 'a replay names a week, a whole number from 1 to 104'),
      (_, null) => null,
      (_, _) => throw BadRequest(reason: 'only a replay names a week, not a ${kind.value}'),
    };
    final (from, to, workoutId) = (
      json.uuidV7OrNull('from'),
      json.uuidV7OrNull('to'),
      json.uuidV7OrNull('workoutId'),
    );
    final advance = kind == .advance;
    if (advance && (from == null || to == null)) {
      throw const BadRequest(reason: 'an advance names the exercise it moved from and to');
    }
    if (!advance && (from != null || to != null)) {
      throw BadRequest(reason: 'only an advance names the exercises it moved from and to, not a ${kind.value}');
    }
    final (exercise, slot) = (json.uuidV7OrNull('exercise'), json.uuidV7OrNull('slot'));
    final staged = kind == .stage;
    final stage = switch ((staged, json['stage'])) {
      (true, final int stage) when stage >= 0 && stage < Stages.maxStages => stage,
      (true, _) => throw const BadRequest(reason: 'a stage names the stage it moved to, a whole number from 0 to 19'),
      (false, null) => null,
      (false, _) => throw BadRequest(reason: 'only a stage names a stage, not a ${kind.value}'),
    };
    if (staged && exercise == null) throw const BadRequest(reason: 'a stage names the exercise it moved');
    if (!staged && (exercise != null || slot != null)) {
      throw BadRequest(reason: 'only a stage names an exercise or a slot, not a ${kind.value}');
    }
    if (!advance && !staged && workoutId != null) {
      throw BadRequest(reason: 'only an advance or a stage names a workout, not a ${kind.value}');
    }
    return ProgramActionIn._(
      ProgramAction(
        id: json.uuidV7OrNull(),
        kind: kind,
        week: week,
        from: from,
        to: to,
        exercise: exercise,
        slot: slot,
        stage: stage,
        workoutId: workoutId,
        at: json.timestamp('at'),
      ),
    );
  }
}

/// `POST /programs/:programId/bases` — `{id?, exerciseId, slot?, value, workoutId?, actionId?, at}`.
/// A base names at most one cause; with none, the user set it.
class ProgramBaseIn {
  final ProgramBase base;

  const new _(this.base);

  static Future<ProgramBaseIn> fromRequest(Request req) async {
    final json = await req.json();
    final workoutId = json.uuidV7OrNull('workoutId');
    final actionId = json.uuidV7OrNull('actionId');
    if (workoutId != null && actionId != null) {
      throw const BadRequest(reason: 'a base has one cause: a workout or an action, not both');
    }
    return ProgramBaseIn._(
      ProgramBase(
        id: json.uuidV7OrNull(),
        exerciseId: switch (json.uuidV7OrNull('exerciseId')) {
          final String id => id,
          null => throw const BadRequest(reason: 'exerciseId is required'),
        },
        slot: json.uuidV7OrNull('slot'),
        value: json.number('value', exclusiveMin: 0),
        workoutId: workoutId,
        actionId: actionId,
        at: json.timestamp('at'),
      ),
    );
  }
}
