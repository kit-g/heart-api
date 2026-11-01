import 'misc.dart';

/// A program in a coach's library, which reaches no client until it is sent.
abstract interface class CoachProgram implements Model {
  String get id;

  String get name;

  /// The current version. A change makes a new one and touches no copy.
  int get version;

  /// The program and its sessions, in the shape a program is created from. Only
  /// when one program was asked for.
  Map<String, dynamic>? get body;

  DateTime get updatedAt;

  factory({
    required String id,
    required String name,
    required int version,
    Map<String, dynamic>? body,
    required DateTime updatedAt,
  }) = _CoachProgram.new;

  factory fromRow(Map row) {
    return CoachProgram(
      id: row['id'].toString(),
      name: row['name'] as String,
      version: row['version'] as int,
      body: (row['body'] as Map?)?.cast<String, dynamic>(),
      updatedAt: row['updated_at'] as DateTime,
    );
  }
}

class _CoachProgram implements CoachProgram {
  @override
  final String id;
  @override
  final String name;
  @override
  final int version;
  @override
  final Map<String, dynamic>? body;
  @override
  final DateTime updatedAt;

  const new({required this.id, required this.name, required this.version, this.body, required this.updatedAt});

  @override
  Map<String, dynamic> toMap() {
    return {'id': id, 'name': name, 'version': version, 'body': ?body, 'updatedAt': updatedAt.toIso8601String()};
  }
}

/// Who holds a library program, and which version.
abstract interface class CoachProgramHolder implements Model {
  String get connectionId;

  String get studentId;

  String? get studentName;

  String? get studentAvatar;

  String get programId;

  int get version;

  factory({
    required String connectionId,
    required String studentId,
    String? studentName,
    String? studentAvatar,
    required String programId,
    required int version,
  }) = _CoachProgramHolder.new;

  factory fromRow(Map row) {
    return CoachProgramHolder(
      connectionId: row['connection_id'].toString(),
      studentId: row['student_id'] as String,
      studentName: row['username'] as String?,
      studentAvatar: row['avatar_url'] as String?,
      programId: row['program_id'].toString(),
      version: row['library_version'] as int,
    );
  }
}

class _CoachProgramHolder implements CoachProgramHolder {
  @override
  final String connectionId;
  @override
  final String studentId;
  @override
  final String? studentName;
  @override
  final String? studentAvatar;
  @override
  final String programId;
  @override
  final int version;

  const new({
    required this.connectionId,
    required this.studentId,
    this.studentName,
    this.studentAvatar,
    required this.programId,
    required this.version,
  });

  @override
  Map<String, dynamic> toMap() {
    return {
      'connectionId': connectionId,
      'studentId': studentId,
      'studentName': ?studentName,
      'studentAvatar': ?studentAvatar,
      'programId': programId,
      'version': version,
    };
  }
}

class CoachProgramHolders implements Model {
  final List<CoachProgramHolder> holders;

  const new(this.holders);

  @override
  Map<String, dynamic> toMap() => {
    'holders': [for (final holder in holders) holder.toMap()],
  };
}

/// What came of sending to one client. [reason] is a code such as `program_limit`
/// when it didn't arrive.
class ProgramDelivery implements Model {
  final String connectionId;
  final bool delivered;
  final String? programId;
  final String? reason;

  const new({required this.connectionId, required this.delivered, this.programId, this.reason});

  @override
  Map<String, dynamic> toMap() {
    return {'connectionId': connectionId, 'delivered': delivered, 'programId': ?programId, 'reason': ?reason};
  }
}

class ProgramDeliveries implements Model {
  final List<ProgramDelivery> deliveries;

  const new(this.deliveries);

  @override
  Map<String, dynamic> toMap() => {
    'deliveries': [for (final delivery in deliveries) delivery.toMap()],
  };
}
