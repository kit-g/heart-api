import 'dart:convert';

import 'auth.dart';
import 'misc.dart';

abstract interface class TemplateShare implements Model {
  String get id;

  String get studentTemplateId;

  String get templateName;

  Profile get assignedTo;

  DateTime get assignedAt;

  factory TemplateShare({
    required String id,
    required String studentTemplateId,
    required String templateName,
    required Profile assignedTo,
    required DateTime assignedAt,
  }) = _TemplateShare;

  factory TemplateShare.fromRow(Map<String, dynamic> row) {
    final studentId = row['student_id'].toString();
    return _TemplateShare(
      id: row['id'].toString(),
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
  final String studentTemplateId;
  @override
  final String templateName;
  @override
  final Profile assignedTo;
  @override
  final DateTime assignedAt;

  const _TemplateShare({
    required this.id,
    required this.studentTemplateId,
    required this.templateName,
    required this.assignedTo,
    required this.assignedAt,
  });

  @override
  TemplateShare copyWith({
    String? studentId,
    String? studentTemplateId,
    String? templateName,
    Profile? assignedTo,
    DateTime? assignedAt,
  }) {
    return _TemplateShare(
      id: id,
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
      'studentTemplateId': studentTemplateId,
      'templateName': templateName,
      'assignedTo': assignedTo.toMap(),
      'assignedAt': assignedAt.toIso8601String(),
    };
  }
}

class TemplateRequest {
  final String userId;
  final Map<String, dynamic> body;

  TemplateRequest({required this.userId, required this.body});

  List<Map> _exercises() {
    return ((body['exercises'] as List? ?? []).cast<Map>()).indexed
        .map(
          (record) {
            final (index, ex) = record;
            final name = switch (ex['exercise']) {
              String s => s,
              {'name': String n} => n,
              _ => null,
            };
            return {
              'exercise_name': name,
              'order': ex['order'] ?? index,
              'sets': ex['sets'] ?? [],
            };
          },
        )
        .where((e) => e['exercise_name'] != null)
        .toList();
  }

  Map<String, dynamic> toParams() {
    return {
      'userId': userId,
      'name': body['name'],
      'orderIndex': (body['order'] as num?)?.toInt() ?? 0,
      'exercises': jsonEncode(_exercises()),
    };
  }
}
