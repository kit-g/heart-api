import 'misc.dart';
import 'program.dart';
import 'tolerant.dart';

/// One program's history as the server holds it: its steps and bases, each
/// oldest first.
class ProgramHistoryOf implements Model {
  final String programId;
  final List<ProgramAction> actions;
  final List<ProgramBase> bases;

  final List<(int, Map)> _unreadActions;
  final List<(int, Map)> _unreadBases;

  const new({required this.programId, this.actions = const [], this.bases = const []})
    : _unreadActions = const [],
      _unreadBases = const [];

  const new _read({
    required this.programId,
    required this.actions,
    required this.bases,
    required List<(int, Map)> unreadActions,
    required List<(int, Map)> unreadBases,
  }) : _unreadActions = unreadActions,
       _unreadBases = unreadBases;

  /// A step or base this build can't read is set aside in [unreadActions] or
  /// [unreadBases], as it arrived, and written back in place by [toMap]. A
  /// missing list is not an empty history: an emptied one arrives as `[]`.
  factory fromJson(Map json) {
    final programId = json['programId'] as String;
    final actions = readIndexed(
      _list(json, 'actions'),
      (each) => ProgramAction.fromJson({...each, 'programId': programId}),
    );
    final bases = readIndexed(_list(json, 'bases'), (each) => ProgramBase.fromJson({...each, 'programId': programId}));
    return ._read(
      programId: programId,
      actions: actions.items,
      bases: bases.items,
      unreadActions: actions.unread,
      unreadBases: bases.unread,
    );
  }

  /// The steps this build couldn't read, as they arrived.
  List<Map> get unreadActions => [for (final (_, json) in _unreadActions) json];

  /// The bases this build couldn't read, as they arrived.
  List<Map> get unreadBases => [for (final (_, json) in _unreadBases) json];

  /// False when something in this history was set aside: [actions] and [bases]
  /// are then not the whole of it for this build.
  bool get isWhole => _unreadActions.isEmpty && _unreadBases.isEmpty;

  /// Each step and base without its `programId`, which the entry carries once.
  @override
  Map<String, dynamic> toMap() {
    return {
      'programId': programId,
      'actions': splice([for (final action in actions) action.toMap()..remove('programId')], _unreadActions),
      'bases': splice([for (final base in bases) base.toMap()..remove('programId')], _unreadBases),
    };
  }
}

List<Object?> _list(Map json, String key) {
  return switch (json[key]) {
    final List<Object?> list => list,
    _ => throw FormatException('a program history without $key'),
  };
}

/// One page of an account's programs whose history changed since a cursor
/// (heart-api#458): each program whole, as it stands now.
class ProgramHistoryChanges implements Model {
  final List<ProgramHistoryOf> programs;

  /// Where the next read starts, opaque. Null only when there has never been
  /// anything to report.
  final String? cursor;

  /// True when this page was cut short: ask again from [cursor] straight away.
  final bool hasMore;

  final List<(int, Map)> _unread;

  const new({required this.programs, required this.cursor, required this.hasMore}) : _unread = const [];

  const new _read({
    required this.programs,
    required this.cursor,
    required this.hasMore,
    required List<(int, Map)> unread,
  }) : _unread = unread;

  /// A program this build can't read is set aside in [unread], as it arrived,
  /// and written back in place by [toMap].
  factory fromJson(Map json) {
    final programs = readIndexed(json['programs'] as List, ProgramHistoryOf.fromJson);
    return ._read(
      programs: programs.items,
      cursor: json['cursor'] as String?,
      hasMore: json['hasMore'] as bool? ?? false,
      unread: programs.unread,
    );
  }

  /// The programs this build couldn't read, as they arrived.
  List<Map> get unread => [for (final (_, json) in _unread) json];

  /// False when a program, or a step or base of one, was set aside.
  bool get isWhole => _unread.isEmpty && programs.every((program) => program.isWhole);

  @override
  Map<String, dynamic> toMap() {
    return {
      'programs': splice([for (final program in programs) program.toMap()], _unread),
      'cursor': ?cursor,
      'hasMore': hasMore,
    };
  }
}
