import 'dart:convert';

import 'auth.dart';
import 'misc.dart';

/// One coach-owned master template, handed to one student.
///
/// Assignment copies rather than references (see `_shareTemplates` in
/// `api/lib/db/queries.dart`), so a share is the ledger entry tying the coach's
/// [masterTemplateId] to the student's [studentTemplateId] copy. Deleting the
/// share deletes the student's copy.
abstract interface class TemplateShare implements Model {
  String get id;

  /// The coach's template this was copied from.
  String get masterTemplateId;

  /// The student's copy, created by the assignment.
  String get studentTemplateId;

  String get templateName;

  Profile get assignedTo;

  DateTime get assignedAt;

  factory({
    required String id,
    required String masterTemplateId,
    required String studentTemplateId,
    required String templateName,
    required Profile assignedTo,
    required DateTime assignedAt,
  }) = _TemplateShare;

  factory fromRow(Map<String, dynamic> row) {
    final studentId = row['student_id'].toString();
    return _TemplateShare(
      id: row['id'].toString(),
      masterTemplateId: row['master_template_id'].toString(),
      studentTemplateId: row['student_template_id'].toString(),
      templateName: row['template_name'] as String,
      assignedTo: Profile(
        id: studentId,
        name: row['student_username'],
        avatar: row['student_avatar'],
      ),
      assignedAt: switch (row['created_at']) {
        DateTime dt => dt,
        String s => DateTime.parse(s),
        _ => DateTime.now(),
      },
    );
  }

  TemplateShare copyWith({
    String? studentId,
    String? masterTemplateId,
    String? studentTemplateId,
    String? templateName,
    Profile? assignedTo,
    DateTime? assignedAt,
  });
}

class _TemplateShare implements TemplateShare {
  @override
  final String id;
  @override
  final String masterTemplateId;
  @override
  final String studentTemplateId;
  @override
  final String templateName;
  @override
  final Profile assignedTo;
  @override
  final DateTime assignedAt;

  const new({
    required this.id,
    required this.masterTemplateId,
    required this.studentTemplateId,
    required this.templateName,
    required this.assignedTo,
    required this.assignedAt,
  });

  @override
  TemplateShare copyWith({
    String? studentId,
    String? masterTemplateId,
    String? studentTemplateId,
    String? templateName,
    Profile? assignedTo,
    DateTime? assignedAt,
  }) {
    return _TemplateShare(
      id: id,
      masterTemplateId: masterTemplateId ?? this.masterTemplateId,
      studentTemplateId: studentTemplateId ?? this.studentTemplateId,
      templateName: templateName ?? this.templateName,
      assignedTo: assignedTo ?? this.assignedTo,
      assignedAt: assignedAt ?? this.assignedAt,
    );
  }

  @override
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'masterTemplateId': masterTemplateId,
      'studentTemplateId': studentTemplateId,
      'templateName': templateName,
      'assignedTo': assignedTo.toMap(),
      'assignedAt': assignedAt.toIso8601String(),
    };
  }
}

/// One set inside a [TemplateExerciseRequest]. Every measure is optional — a
/// bodyweight set has no weight, a timed hold has no reps.
class TemplateSetRequest {
  final num? weight;
  final num? reps;
  final num? duration;
  final num? distance;

  const new({this.weight, this.reps, this.duration, this.distance});

  /// Keys match what `_saveTemplate` reads out of the `@exercises` jsonb.
  Map<String, dynamic> toJson() {
    return {
      'weight': ?weight,
      'reps': ?reps,
      'duration': ?duration,
      'distance': ?distance,
    };
  }
}

/// One exercise in a template body, addressed **by id** — the uuid is the
/// exercise's identity; its name is localized display copy. (Assigned-template
/// resolution onto a student's own variants happens server-side at share time,
/// not through this reference.)
class TemplateExerciseRequest {
  final String exerciseId;
  final int order;
  final List<TemplateSetRequest> sets;

  const new({
    required this.exerciseId,
    required this.order,
    this.sets = const [],
  });

  Map<String, dynamic> toJson() {
    return {
      'exercise_id': exerciseId,
      'order': order,
      'sets': sets.map((s) => s.toJson()).toList(),
    };
  }
}

/// A validated template write, ready for `_saveTemplate` / `_replaceTemplate`.
///
/// Typed rather than a raw body map: HTTP shape-checking belongs in the API's
/// input layer (`api/lib/inputs/templates.dart`), which is what builds this.
class TemplateRequest {
  final String userId;

  /// The template's own client-minted id (heart-api#66). Only a create
  /// reads this — an update addresses its template by path parameter, same as
  /// before. Absent, the insert mints one.
  final String? id;

  final String? name;
  final int order;

  /// The folder to file the template under. On an update this is only consulted
  /// when [movesFolder] is true; null with [movesFolder] set means "unfile".
  final String? folderId;

  /// Whether the request spoke about filing at all. Only an update cares — see
  /// `_replaceTemplate`, which leaves `folder_id` alone when this is false.
  final bool movesFolder;

  final List<TemplateExerciseRequest> exercises;

  const new({
    required this.userId,
    this.id,
    this.name,
    this.order = 0,
    this.folderId,
    this.movesFolder = false,
    this.exercises = const [],
  });

  /// Deliberately omits [id] — `_replaceTemplate` (unlike `_saveTemplate`) has
  /// no `@id` placeholder, and the postgres client rejects a superfluous named
  /// parameter, so a create merges `id` in itself rather than carrying it here.
  Map<String, dynamic> toParams() {
    return {
      'userId': userId,
      'name': name,
      'orderIndex': order,
      'folderId': folderId,
      'exercises': jsonEncode(exercises.map((e) => e.toJson()).toList()),
    };
  }
}
