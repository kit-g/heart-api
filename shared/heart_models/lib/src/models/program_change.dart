import 'misc.dart';
import 'program.dart';
import 'template.dart';
import 'tolerant.dart';

/// One change to a coach's copy of a program: who, what and when, with how it stood.
abstract interface class ProgramChange implements Model {
  String get id;

  String get programId;

  /// The session it touched; null for the program's own fields.
  String? get sessionId;

  String? get actorId;

  /// `edit`, `create`, `delete`, `revert` or `library_update`, and a later server
  /// may add a word.
  String get kind;

  /// The session's or program's revision after it.
  int get revision;

  Map<String, dynamic>? get before;

  Map<String, dynamic>? get after;

  /// Written by a build that sends no revision, so it may have overwritten
  /// something it never saw. What it overwrote is in [before].
  bool get stale;

  DateTime get at;

  /// Its place in the stored order, opaque, for reading what changed since.
  String? get cursor;

  factory({
    required String id,
    required String programId,
    String? sessionId,
    String? actorId,
    required String kind,
    required int revision,
    Map<String, dynamic>? before,
    Map<String, dynamic>? after,
    bool stale,
    required DateTime at,
    String? cursor,
  }) = _ProgramChange.new;

  factory fromRow(Map row, {String? cursor}) {
    return ProgramChange(
      id: row['id'].toString(),
      programId: row['program_id'].toString(),
      sessionId: row['session_id']?.toString(),
      actorId: row['actor_id'] as String?,
      kind: row['kind'] as String,
      revision: row['revision'] as int,
      before: (row['before'] as Map?)?.cast<String, dynamic>(),
      after: (row['after'] as Map?)?.cast<String, dynamic>(),
      stale: row['stale'] as bool? ?? false,
      at: row['at'] as DateTime,
      cursor: cursor,
    );
  }

  factory fromJson(Map json) {
    return ProgramChange(
      id: json['id'] as String,
      programId: json['programId'] as String,
      sessionId: json['sessionId'] as String?,
      actorId: json['actorId'] as String?,
      kind: json['kind'] as String,
      revision: (json['revision'] as num).toInt(),
      before: (json['before'] as Map?)?.cast<String, dynamic>(),
      after: (json['after'] as Map?)?.cast<String, dynamic>(),
      stale: json['stale'] as bool? ?? false,
      at: DateTime.parse(json['at'] as String),
      cursor: json['cursor'] as String?,
    );
  }
}

class _ProgramChange implements ProgramChange {
  @override
  final String id;
  @override
  final String programId;
  @override
  final String? sessionId;
  @override
  final String? actorId;
  @override
  final String kind;
  @override
  final int revision;
  @override
  final Map<String, dynamic>? before;
  @override
  final Map<String, dynamic>? after;
  @override
  final bool stale;
  @override
  final DateTime at;
  @override
  final String? cursor;

  const new({
    required this.id,
    required this.programId,
    this.sessionId,
    this.actorId,
    required this.kind,
    required this.revision,
    this.before,
    this.after,
    this.stale = false,
    required this.at,
    this.cursor,
  });

  @override
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'programId': programId,
      'sessionId': ?sessionId,
      'actorId': ?actorId,
      'kind': kind,
      'revision': revision,
      'before': ?before,
      'after': ?after,
      if (stale) 'stale': true,
      'at': at.toIso8601String(),
      'cursor': ?cursor,
    };
  }
}

/// What changed on a copy, in order.
class ProgramChanges implements Model {
  final List<ProgramChange> changes;

  const new(this.changes);

  /// A change this build can't read is left out.
  factory fromJson(Map json) => ProgramChanges(readIndexed(json['changes'], ProgramChange.fromJson).items);

  @override
  Map<String, dynamic> toMap() => {
    'changes': [for (final change in changes) change.toMap()],
  };
}

/// What a device planned for a workout, as it stood.
class WorkoutPlan implements Model {
  final Map<String, dynamic> plan;

  const new(this.plan);

  factory fromJson(Map json) => WorkoutPlan((json['plan'] as Map).cast<String, dynamic>());

  @override
  Map<String, dynamic> toMap() => {'plan': plan};
}

/// What a coach reads of a copy: worked out only from what they can read, so a
/// hidden workout leaves its session undone here, and the week can trail the
/// student's own.
class CoachProgramView implements Model {
  final Program program;
  final List<Template> sessions;
  final Map<String, dynamic> position;

  const new({required this.program, required this.sessions, required this.position});

  /// A session this build can't read is left out.
  factory fromJson(Map json) {
    return CoachProgramView(
      program: Program.fromJson(json['program'] as Map),
      sessions: readIndexed(json['sessions'], Template.fromJson).items,
      position: (json['position'] as Map).cast<String, dynamic>(),
    );
  }

  @override
  Map<String, dynamic> toMap() {
    return {
      'program': program.toMap(),
      'sessions': [for (final session in sessions) session.toMap()],
      'position': position,
    };
  }
}
