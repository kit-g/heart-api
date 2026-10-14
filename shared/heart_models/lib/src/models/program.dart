import 'dart:convert';

import 'misc.dart';

/// How one exercise's base grows over a program: what is raised, and when.
///
/// The base is the one number a rule grows: the training max under
/// [ShareOfMax], the working weight under [AddWeight] and [RangeThenWeight],
/// the duration or distance under [Longer]. [NoGrowth] leaves the sets as
/// written.
///
/// [fromJson] is strict: an unknown kind, a missing parameter or one out of
/// range is an [ArgumentError]. [Program.fromJson] catches that and carries the
/// rule as it arrived, so a newer kind survives an older build's save.
sealed class GrowthRule implements Model {
  const new();

  /// The `kind` on the wire.
  String get kind;

  Map<String, dynamic> get _parameters;

  factory fromJson(Map json) {
    return switch (json['kind']) {
      NoGrowth.key => const NoGrowth(),
      AddWeight.key => AddWeight(step: _positive(json, 'step')),
      RangeThenWeight.key => RangeThenWeight(step: _positive(json, 'step')),
      Longer.key => Longer(step: _positive(json, 'step')),
      ShareOfMax.key => ShareOfMax(
        waves: switch (json['waves']) {
          final List waves when waves.isNotEmpty => [for (final wave in waves) _wave(wave)],
          _ => throw ArgumentError.value(json['waves'], 'waves', 'a non-empty list of weeks'),
        },
        step: _positive(json, 'step'),
        missCut: switch (json['missCut']) {
          null => ShareOfMax.defaultMissCut,
          final num cut when cut > 0 && cut < 1 => cut,
          final other => throw ArgumentError.value(other, 'missCut', 'a share between 0 and 1'),
        },
        misses: switch (json['misses']) {
          null => ShareOfMax.defaultMisses,
          final int misses when misses >= 1 => misses,
          final other => throw ArgumentError.value(other, 'misses', 'a whole number of at least 1'),
        },
      ),
      final other => throw ArgumentError.value(other, 'kind', 'unknown growth rule'),
    };
  }

  @override
  Map<String, dynamic> toMap() => {'kind': kind, ..._parameters};

  @override
  bool operator ==(Object other) {
    return other is GrowthRule && jsonEncode(other.toMap()) == jsonEncode(toMap());
  }

  @override
  int get hashCode => jsonEncode(toMap()).hashCode;

  @override
  String toString() => 'GrowthRule(${toMap()})';
}

/// The sets stay as written, every time.
final class NoGrowth extends GrowthRule {
  static const key = 'none';

  const new();

  @override
  String get kind => key;

  @override
  Map<String, dynamic> get _parameters => const {};
}

/// The working weight goes up by [step] kilograms after every completed session.
final class AddWeight extends GrowthRule {
  static const key = 'addWeight';

  final num step;

  const new({required this.step});

  @override
  String get kind => key;

  @override
  Map<String, dynamic> get _parameters => {'step': step};
}

/// The working weight goes up by [step] kilograms once every set reaches the
/// top of its rep range. The range is the session's set target, never the rule's.
final class RangeThenWeight extends GrowthRule {
  static const key = 'rangeThenWeight';

  final num step;

  const new({required this.step});

  @override
  String get kind => key;

  @override
  Map<String, dynamic> get _parameters => {'step': step};
}

/// The duration (seconds) or distance (kilometres) goes up by [step] after
/// every completed cycle.
final class Longer extends GrowthRule {
  static const key = 'longer';

  final num step;

  const new({required this.step});

  @override
  String get kind => key;

  @override
  Map<String, dynamic> get _parameters => {'step': step};
}

/// Sets as a share of a training max that changes by program week, 5/3/1 style.
///
/// [waves] has one entry per program week and repeats: week 5 of a four-week
/// wave is its first week again. Each entry is applied to the session's working
/// sets in order. The max grows by [step] kilograms when a cycle's AMRAP set
/// makes its reps, and drops by [missCut] of itself after [misses] misses.
final class ShareOfMax extends GrowthRule {
  static const key = 'shareOfMax';
  static const defaultMissCut = 0.1;
  static const defaultMisses = 2;

  final List<List<WaveSet>> waves;
  final num step;
  final num missCut;
  final int misses;

  const new({
    required this.waves,
    required this.step,
    this.missCut = defaultMissCut,
    this.misses = defaultMisses,
  });

  /// The sets of program [week], counting from 1.
  List<WaveSet> week(int week) => waves[(week - 1) % waves.length];

  @override
  String get kind => key;

  @override
  Map<String, dynamic> get _parameters {
    return {
      'waves': [
        for (final wave in waves) [for (final set in wave) set.toMap()],
      ],
      'step': step,
      'missCut': missCut,
      'misses': misses,
    };
  }
}

/// One working set of a [ShareOfMax] week: [share] of the training max for
/// [reps], or at least [reps] when [amrap].
final class WaveSet implements Model {
  final num share;
  final int reps;
  final bool amrap;

  const new({required this.share, required this.reps, this.amrap = false});

  factory fromJson(Map json) {
    return WaveSet(
      share: switch (json['share']) {
        final num share when share > 0 && share <= 2 => share,
        final other => throw ArgumentError.value(other, 'share', 'a share of the max, above 0 and at most 2'),
      },
      reps: switch (json['reps']) {
        final int reps when reps >= 1 => reps,
        final other => throw ArgumentError.value(other, 'reps', 'a whole number of at least 1'),
      },
      amrap: switch (json['amrap']) {
        null || false => false,
        true => true,
        final other => throw ArgumentError.value(other, 'amrap', 'a boolean'),
      },
    );
  }

  @override
  Map<String, dynamic> toMap() => {'share': share, 'reps': reps, if (amrap) 'amrap': true};
}

List<WaveSet> _wave(Object? wave) {
  return switch (wave) {
    final List sets when sets.isNotEmpty => [
      for (final set in sets)
        switch (set) {
          final Map set => WaveSet.fromJson(set),
          _ => throw ArgumentError.value(set, 'waves', 'a wave set is an object'),
        },
    ],
    _ => throw ArgumentError.value(wave, 'waves', 'each week is a non-empty list of sets'),
  };
}

num _positive(Map json, String key) {
  return switch (json[key]) {
    final num value when value > 0 => value,
    final other => throw ArgumentError.value(other, key, 'a number above 0'),
  };
}

/// Templates on a plan, with targets that grow (heart-api#86). The design is
/// `docs/2026-10-13.programs.md`.
///
/// A program owns its sessions: they are the user's templates carrying its id,
/// in [sessions] order. Where the user stands (the week, the next session) is
/// computed from workouts, skips and program actions, never stored here.
abstract interface class Program implements Model {
  String? get id;

  String get name;

  String? get note;

  /// The library program this one was copied from, when it was.
  String? get source;

  /// The weekly target, in sessions. Offered, never enforced.
  int? get perWeek;

  /// Preferred ISO weekdays (1 Monday … 7 Sunday): a hint for reminders and for
  /// which session to suggest, never a gate.
  Set<int> get days;

  /// The length in program weeks; null runs on.
  int? get weeks;

  /// The growth rule of each exercise, by exercise id. An exercise without one
  /// is done as written.
  Map<String, GrowthRule> get rules;

  /// A content key, such as `avoid_high_axial_load`, that filters suggestions
  /// inside the program.
  String? get constraint;

  bool get archived;

  /// The ids of the program's session templates, in order. Read-only: a
  /// session joins or leaves through its template.
  List<String> get sessions;

  DateTime? get createdAt;

  /// Rules this build could not read, by exercise id, as they arrived.
  /// [toMap] writes them back, so a save by this build never drops them.
  Map<String, Map> get unreadRules;

  factory({
    String? id,
    required String name,
    String? note,
    String? source,
    int? perWeek,
    Set<int> days,
    int? weeks,
    Map<String, GrowthRule> rules,
    String? constraint,
    bool archived,
    List<String> sessions,
    DateTime? createdAt,
    Map<String, Map> unreadRules,
  }) = _Program;

  /// The wire shape (camelCase).
  factory fromJson(Map json) => _Program._read(json, created: json['createdAt']);

  /// A row of `_programs`: snake_case columns, `rules` as JSONB.
  factory fromRow(Map row) {
    return _Program._read(
      {
        ...row,
        'perWeek': row['per_week'],
        'constraint': row['constraint_key'],
        'createdAt': row['created_at'],
      },
      created: row['created_at'],
    );
  }

  Program copyWith({
    String? name,
    String? note,
    int? perWeek,
    Set<int>? days,
    int? weeks,
    Map<String, GrowthRule>? rules,
    String? constraint,
    bool? archived,
  });
}

class _Program implements Program {
  @override
  final String? id;
  @override
  final String name;
  @override
  final String? note;
  @override
  final String? source;
  @override
  final int? perWeek;
  @override
  final Set<int> days;
  @override
  final int? weeks;
  @override
  final Map<String, GrowthRule> rules;
  @override
  final String? constraint;
  @override
  final bool archived;
  @override
  final List<String> sessions;
  @override
  final DateTime? createdAt;
  @override
  final Map<String, Map> unreadRules;

  new({
    this.id,
    required this.name,
    this.note,
    this.source,
    this.perWeek,
    this.days = const {},
    this.weeks,
    this.rules = const {},
    this.constraint,
    this.archived = false,
    this.sessions = const [],
    this.createdAt,
    this.unreadRules = const {},
  });

  factory _read(Map json, {required Object? created}) {
    final rules = <String, GrowthRule>{};
    final unread = <String, Map>{};
    final raw = switch (json['rules']) {
      final String s => jsonDecode(s),
      final other => other,
    };
    if (raw case final Map raw) {
      for (final MapEntry(:key, :value) in raw.entries) {
        if (value is! Map) continue;
        try {
          rules['$key'] = GrowthRule.fromJson(value);
        } on ArgumentError {
          unread['$key'] = value;
        } on TypeError {
          unread['$key'] = value;
        }
      }
    }
    return _Program(
      id: json['id']?.toString(),
      name: json['name'] as String,
      note: json['note'] as String?,
      source: json['source'] as String?,
      perWeek: (json['perWeek'] as num?)?.toInt(),
      days: {
        for (final day in (json['days'] as List?) ?? const []) (day as num).toInt(),
      },
      weeks: (json['weeks'] as num?)?.toInt(),
      rules: rules,
      constraint: json['constraint'] as String?,
      archived: json['archived'] == true,
      sessions: [
        for (final id in (json['sessions'] as List?) ?? const []) id.toString(),
      ],
      createdAt: switch (created) {
        final DateTime c => c,
        final String c => DateTime.parse(c),
        _ => null,
      },
      unreadRules: unread,
    );
  }

  @override
  Program copyWith({
    String? name,
    String? note,
    int? perWeek,
    Set<int>? days,
    int? weeks,
    Map<String, GrowthRule>? rules,
    String? constraint,
    bool? archived,
  }) {
    return _Program(
      id: id,
      name: name ?? this.name,
      note: note ?? this.note,
      source: source,
      perWeek: perWeek ?? this.perWeek,
      days: days ?? this.days,
      weeks: weeks ?? this.weeks,
      rules: rules ?? this.rules,
      constraint: constraint ?? this.constraint,
      archived: archived ?? this.archived,
      sessions: sessions,
      createdAt: createdAt,
      // a rule the user set for an exercise replaces one this build couldn't read
      unreadRules: {
        for (final MapEntry(:key, :value) in unreadRules.entries)
          if (rules == null || !rules.containsKey(key)) key: value,
      },
    );
  }

  @override
  Map<String, dynamic> toMap() {
    final days = this.days.toList()..sort();
    return {
      'id': ?id,
      'name': name,
      'note': ?note,
      'source': ?source,
      'perWeek': ?perWeek,
      if (days.isNotEmpty) 'days': days,
      'weeks': ?weeks,
      'rules': {
        ...unreadRules,
        for (final MapEntry(:key, :value) in rules.entries) key: value.toMap(),
      },
      'constraint': ?constraint,
      'archived': archived,
      'sessions': sessions,
      'createdAt': ?createdAt?.toUtc().toIso8601String(),
    };
  }

  @override
  bool operator ==(Object other) => other is Program && other.id != null && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'Program(${toMap()})';
}

/// How the user steers a program: the steps a fold over its history takes
/// besides workouts and skips.
enum ProgramActionKind {
  /// Runs the cycle again at the same week: the one just finished when nothing
  /// is done in the open cycle yet, the open one otherwise.
  repeat('repeat'),

  /// Steps the program aside: out of "up next" and the weekly count.
  pause('pause'),

  /// Brings a paused program back. A program workout resumes one as well.
  resume('resume'),

  /// Goes back to [ProgramAction.week].
  replay('replay');

  /// The `kind` on the wire.
  final String value;

  new(this.value);

  factory fromString(String value) {
    return values.firstWhere(
      (each) => each.value == value,
      orElse: () => throw ArgumentError.value(value, 'kind', 'unknown program action'),
    );
  }
}

/// One step the user took in a program, at a moment. Undoing it is deleting it.
abstract interface class ProgramAction implements Model {
  String? get id;

  String? get programId;

  ProgramActionKind get kind;

  /// The week a [ProgramActionKind.replay] goes back to, from 1; null otherwise.
  int? get week;

  /// When the user took it, by the device's clock.
  DateTime get at;

  factory({String? id, String? programId, required ProgramActionKind kind, int? week, required DateTime at}) =
      _ProgramAction;

  factory fromJson(Map json) {
    return _ProgramAction(
      id: json['id']?.toString(),
      programId: json['programId']?.toString(),
      kind: ProgramActionKind.fromString(json['kind'] as String),
      week: (json['week'] as num?)?.toInt(),
      at: DateTime.parse(json['at'] as String),
    );
  }

  factory fromRow(Map row) {
    return _ProgramAction(
      id: row['id']?.toString(),
      programId: row['program_id']?.toString(),
      kind: ProgramActionKind.fromString(row['kind'] as String),
      week: (row['week'] as num?)?.toInt(),
      at: switch (row['at']) {
        final DateTime at => at,
        final String at => DateTime.parse(at),
        final other => throw ArgumentError.value(other, 'at'),
      },
    );
  }
}

class _ProgramAction implements ProgramAction {
  @override
  final String? id;
  @override
  final String? programId;
  @override
  final ProgramActionKind kind;
  @override
  final int? week;
  @override
  final DateTime at;

  new({this.id, this.programId, required this.kind, this.week, required this.at});

  @override
  Map<String, dynamic> toMap() {
    return {
      'id': ?id,
      'programId': ?programId,
      'kind': kind.value,
      'week': ?week,
      'at': at.toUtc().toIso8601String(),
    };
  }
}

/// One value of an exercise's base in a program: the number its growth rule
/// grows (a training max, a working weight, a duration or a distance), in
/// kilograms, seconds or kilometres. The current base is the latest.
///
/// It says what caused it: a workout (a bump the rule made), an action (a
/// replay's cut), or neither (the user set it). Deleting the cause deletes it.
abstract interface class ProgramBase implements Model {
  String? get id;

  String? get programId;

  String get exerciseId;

  num get value;

  String? get workoutId;

  String? get actionId;

  DateTime get at;

  /// Set by the user, not by a workout or an action.
  bool get isManual;

  factory({
    String? id,
    String? programId,
    required String exerciseId,
    required num value,
    String? workoutId,
    String? actionId,
    required DateTime at,
  }) = _ProgramBase;

  factory fromJson(Map json) {
    return _ProgramBase(
      id: json['id']?.toString(),
      programId: json['programId']?.toString(),
      exerciseId: json['exerciseId'] as String,
      value: json['value'] as num,
      workoutId: json['workoutId'] as String?,
      actionId: json['actionId'] as String?,
      at: DateTime.parse(json['at'] as String),
    );
  }

  factory fromRow(Map row) {
    return _ProgramBase(
      id: row['id']?.toString(),
      programId: row['program_id']?.toString(),
      exerciseId: row['exercise_id'].toString(),
      value: row['value'] as num,
      workoutId: row['workout_id']?.toString(),
      actionId: row['action_id']?.toString(),
      at: switch (row['at']) {
        final DateTime at => at,
        final String at => DateTime.parse(at),
        final other => throw ArgumentError.value(other, 'at'),
      },
    );
  }
}

class _ProgramBase implements ProgramBase {
  @override
  final String? id;
  @override
  final String? programId;
  @override
  final String exerciseId;
  @override
  final num value;
  @override
  final String? workoutId;
  @override
  final String? actionId;
  @override
  final DateTime at;

  new({
    this.id,
    this.programId,
    required this.exerciseId,
    required this.value,
    this.workoutId,
    this.actionId,
    required this.at,
  });

  @override
  bool get isManual => workoutId == null && actionId == null;

  @override
  Map<String, dynamic> toMap() {
    return {
      'id': ?id,
      'programId': ?programId,
      'exerciseId': exerciseId,
      'value': value,
      'workoutId': ?workoutId,
      'actionId': ?actionId,
      'at': at.toUtc().toIso8601String(),
    };
  }
}
