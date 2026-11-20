import 'misc.dart';
import 'program.dart';
import 'tolerant.dart';

/// One program's steps and bases, each oldest first.
typedef ProgramHistoryOf = ({String programId, List<ProgramAction> actions, List<ProgramBase> bases});

/// One page of an account's programs whose history changed since a cursor
/// (heart-api#458): each program whole, as it stands now.
class ProgramHistoryChanges implements Model {
  final List<ProgramHistoryOf> programs;

  /// Where the next read starts, opaque. Null only when there has never been
  /// anything to report.
  final String? cursor;

  /// True when this page was cut short: ask again from [cursor] straight away.
  final bool hasMore;

  const new({required this.programs, required this.cursor, required this.hasMore});

  /// A step or base this build can't read is left out of its program.
  factory fromJson(Map json) {
    return ProgramHistoryChanges(
      programs: [
        for (final program in json['programs'] as List)
          (
            programId: (program as Map)['programId'] as String,
            actions: readIndexed(program['actions'], ProgramAction.fromJson).items,
            bases: readIndexed(program['bases'], ProgramBase.fromJson).items,
          ),
      ],
      cursor: json['cursor'] as String?,
      hasMore: json['hasMore'] as bool? ?? false,
    );
  }

  @override
  Map<String, dynamic> toMap() {
    return {
      'programs': [
        for (final (:programId, :actions, :bases) in programs)
          {
            'programId': programId,
            'actions': [for (final action in actions) action.toMap()],
            'bases': [for (final base in bases) base.toMap()],
          },
      ],
      'cursor': ?cursor,
      'hasMore': hasMore,
    };
  }
}
