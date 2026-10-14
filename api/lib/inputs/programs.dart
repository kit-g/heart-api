part of 'inputs.dart';

/// `POST /programs` — the program and its sessions:
/// `{id?, name, note?, source?, perWeek?, days?, weeks?, rules?, constraint?, sessions: [template, ...]}`.
///
/// Each session is a template body, as `POST /templates` takes one, and becomes
/// a template of the program. Starting a library program is this call: the
/// device makes the copy and sends it whole.
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

final _programKey = RegExp(r'^[a-z][a-z0-9_]{0,63}$');

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
      final String key when _programKey.hasMatch(key) => key,
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
          _ => throw BadRequest(code: 'invalid_rule', reason: 'rules keys are exercise ids; $key is not one'),
        }: switch (value) {
          final Map rule => _rule(key, rule),
          _ => throw BadRequest(code: 'invalid_rule', reason: 'rules.$key must be an object'),
        },
    };
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
  return rule;
}

/// `POST /programs/:programId/actions` — `{id?, kind, week?, at}`. Only a
/// replay names a week.
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
    return ProgramActionIn._(
      ProgramAction(id: json.uuidV7OrNull(), kind: kind, week: week, at: json.timestamp('at')),
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
