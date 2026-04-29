import 'dart:convert';

import 'package:heart_models/heart_models.dart';

abstract interface class TemplateShareItem implements Model {
  String get id;

  String get studentTemplateId;

  String get templateName;

  Profile get assignedTo;

  DateTime get assignedAt;

  factory TemplateShareItem({
    required String id,
    required String studentTemplateId,
    required String templateName,
    required Profile assignedTo,
    required DateTime assignedAt,
  }) = _TemplateShareItem;

  factory TemplateShareItem.fromRow(Map<String, dynamic> row) {
    return _TemplateShareItem(
      id: switch ((row['SK'] as String).split('#')) {
        [_, String templateId, String userId] => '$userId|$templateId',
        _ => throw ArgumentError('Invalid template share ID'),
      },
      studentTemplateId: row['student_template_id'] as String,
      templateName: row['template_name'] as String,
      assignedTo: Profile.fromJson(row['assigned_to'] as Map),
      assignedAt: DateTime.parse(row['assigned_at'] as String),
    );
  }

  TemplateShareItem copyWith({
    String? studentId,
    String? studentTemplateId,
    String? templateName,
    Profile? assignedTo,
    DateTime? assignedAt,
  });
}

class _TemplateShareItem implements TemplateShareItem {
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

  const _TemplateShareItem({
    required this.id,
    required this.studentTemplateId,
    required this.templateName,
    required this.assignedTo,
    required this.assignedAt,
  });

  @override
  TemplateShareItem copyWith({
    String? studentId,
    String? studentTemplateId,
    String? templateName,
    Profile? assignedTo,
    DateTime? assignedAt,
  }) {
    return _TemplateShareItem(
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



abstract interface class TemplateShareListResponse implements Model, Iterable<TemplateShareItem> {
  List<TemplateShareItem> get shares;

  String? get cursor;

  factory TemplateShareListResponse({
    required List<TemplateShareItem> shares,
    required String? cursor,
  }) = _TemplateShareListResponse;
}

class _TemplateShareListResponse with Iterable<TemplateShareItem> implements TemplateShareListResponse {
  @override
  final List<TemplateShareItem> shares;
  @override
  final String? cursor;

  const _TemplateShareListResponse({required this.shares, required this.cursor});

  @override
  Iterator<TemplateShareItem> get iterator => shares.iterator;

  @override
  Map<String, dynamic> toMap() {
    return {
      'shares': map((s) => s.toMap()).toList(),
      'cursor': ?cursor,
    };
  }
}

abstract interface class ApiTemplateService {
  Future<Template> createTemplate({required String userId, required TemplateRequest body});

  Future<Template> updateTemplate({
    required String userId,
    required String templateId,
    required TemplateRequest body,
  });

  Future<TemplateShareItem> shareTemplate({
    required String coachId,
    required String targetUserId,
    required String masterTemplateId,
  });

  Future<TemplateResponse> getTemplates({required String userId, String? cursor, int? pageSize});

  Future<TemplateShareListResponse> getTemplateShares({required String userId, String? cursor, int? pageSize});

  Future<void> deleteTemplate({required String coachId, required String templateId});

  Future<void> deleteShare({required String coachId, required String shareId});
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
            return {'exercise_name': name, 'order': ex['order'] ?? index, 'sets': ex['sets'] ?? []};
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
