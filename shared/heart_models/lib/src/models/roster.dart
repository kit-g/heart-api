import 'misc.dart';

/// Why a client needs a word. `lighter`, `note`, `gap`, `ending`, and a later server
/// may add one, so these travel as text.
abstract interface class ClientSummary implements Model {
  String get connectionId;

  String get studentId;

  String? get name;

  String? get avatar;

  /// `active`, `paused`, or `severed` for a former client.
  String get status;

  DateTime? get acceptedAt;

  String? get programId;

  String? get programName;

  int? get programWeek;

  int? get programWeeks;

  /// When they trained lately. The coach's device turns these into days.
  List<DateTime> get recent;

  DateTime? get lastTrainedAt;

  List<String> get reasons;

  factory({
    required String connectionId,
    required String studentId,
    String? name,
    String? avatar,
    required String status,
    DateTime? acceptedAt,
    String? programId,
    String? programName,
    int? programWeek,
    int? programWeeks,
    List<DateTime> recent,
    DateTime? lastTrainedAt,
    List<String> reasons,
  }) = _ClientSummary.new;

  factory fromRow(Map row) {
    return ClientSummary(
      connectionId: row['connection_id'].toString(),
      studentId: row['student_id'] as String,
      name: row['username'] as String?,
      avatar: row['avatar_url'] as String?,
      status: row['status'] as String,
      acceptedAt: row['accepted_at'] as DateTime?,
      programId: row['program_id']?.toString(),
      programName: row['program_name'] as String?,
      programWeek: row['program_week'] as int?,
      programWeeks: row['program_weeks'] as int?,
      recent: [for (final at in (row['recent'] as List?) ?? const []) at as DateTime],
      lastTrainedAt: row['last_trained_at'] as DateTime?,
      reasons: [for (final reason in (row['reasons'] as List?) ?? const []) '$reason'],
    );
  }
}

class _ClientSummary implements ClientSummary {
  @override
  final String connectionId;
  @override
  final String studentId;
  @override
  final String? name;
  @override
  final String? avatar;
  @override
  final String status;
  @override
  final DateTime? acceptedAt;
  @override
  final String? programId;
  @override
  final String? programName;
  @override
  final int? programWeek;
  @override
  final int? programWeeks;
  @override
  final List<DateTime> recent;
  @override
  final DateTime? lastTrainedAt;
  @override
  final List<String> reasons;

  const new({
    required this.connectionId,
    required this.studentId,
    this.name,
    this.avatar,
    required this.status,
    this.acceptedAt,
    this.programId,
    this.programName,
    this.programWeek,
    this.programWeeks,
    this.recent = const [],
    this.lastTrainedAt,
    this.reasons = const [],
  });

  @override
  Map<String, dynamic> toMap() {
    return {
      'connectionId': connectionId,
      'studentId': studentId,
      'name': ?name,
      'avatar': ?avatar,
      'status': status,
      'acceptedAt': ?acceptedAt?.toIso8601String(),
      'programId': ?programId,
      'programName': ?programName,
      'programWeek': ?programWeek,
      'programWeeks': ?programWeeks,
      'recent': [for (final at in recent) at.toIso8601String()],
      'lastTrainedAt': ?lastTrainedAt?.toIso8601String(),
      'reasons': reasons,
    };
  }
}

/// One thing in a coach's feed: a workout finished, a session skipped, a program ending.
abstract interface class CoachFeedItem implements Model {
  /// `workout`, `skip` or `ending`, and a later server may add a word.
  String get kind;

  String get id;

  String get studentId;

  String? get name;

  String? get avatar;

  DateTime get at;

  /// The workout's name, or the program's.
  String? get title;

  String? get cursor;

  factory({
    required String kind,
    required String id,
    required String studentId,
    String? name,
    String? avatar,
    required DateTime at,
    String? title,
    String? cursor,
  }) = _CoachFeedItem.new;

  factory fromRow(Map row, {String? cursor}) {
    return CoachFeedItem(
      kind: row['kind'] as String,
      id: row['id'].toString(),
      studentId: row['student_id'] as String,
      name: row['username'] as String?,
      avatar: row['avatar_url'] as String?,
      at: row['at'] as DateTime,
      title: row['title'] as String?,
      cursor: cursor,
    );
  }
}

class _CoachFeedItem implements CoachFeedItem {
  @override
  final String kind;
  @override
  final String id;
  @override
  final String studentId;
  @override
  final String? name;
  @override
  final String? avatar;
  @override
  final DateTime at;
  @override
  final String? title;
  @override
  final String? cursor;

  const new({
    required this.kind,
    required this.id,
    required this.studentId,
    this.name,
    this.avatar,
    required this.at,
    this.title,
    this.cursor,
  });

  @override
  Map<String, dynamic> toMap() {
    return {
      'kind': kind,
      'id': id,
      'studentId': studentId,
      'name': ?name,
      'avatar': ?avatar,
      'at': at.toIso8601String(),
      'title': ?title,
    };
  }
}
