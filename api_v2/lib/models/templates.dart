import 'package:heart/models/av.dart';
import 'package:heart/models/profile.dart';
import 'package:heart/models/workouts.dart';
import 'package:heart_models/heart_models.dart';

abstract interface class TemplateItem implements DynamoItem, Iterable<ExerciseItem>, Model {
  String get id;

  String get name;

  int get order;

  List<ExerciseItem> get exercises;

  String? get sourceTemplateId;

  Profile? get assignedBy;

  bool? get syncEnabled;

  factory TemplateItem.fromRow(Map<String, dynamic> row) {
    final sk = row['SK'] as String;
    return _TemplateItem(
      id: sk.replaceFirst('TEMPLATE#', ''),
      name: row['name'] as String,
      order: (row['order'] as num?)?.toInt() ?? 0,
      exercises: switch (row['exercises']) {
        List l => l.map((each) => ExerciseItem.fromRow(each)).toList(),
        _ => [],
      },
      sourceTemplateId: row['source_template_id'] as String?,
      assignedBy: switch (row['assigned_by']) {
        Map m => Profile.fromJson(m),
        _ => null,
      },
      syncEnabled: row['sync_enabled'] as bool?,
    );
  }

  TemplateItem copyWith({
    String? id,
    String? name,
    int? order,
    List<ExerciseItem>? exercises,
    String? sourceTemplateId,
    Profile? assignedBy,
  });
}

class _TemplateItem with Iterable<ExerciseItem> implements TemplateItem {
  @override
  final String id;
  @override
  final String name;
  @override
  final int order;
  @override
  final List<ExerciseItem> exercises;
  @override
  final String? sourceTemplateId;
  @override
  final Profile? assignedBy;
  @override
  final bool? syncEnabled;

  const _TemplateItem({
    required this.id,
    required this.name,
    required this.order,
    required this.exercises,
    this.sourceTemplateId,
    this.assignedBy,
    this.syncEnabled,
  });

  @override
  Iterator<ExerciseItem> get iterator => exercises.iterator;

  @override
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'order': order,
      'exercises': exercises.map((ex) => ex.toMap()).toList(),
      'sourceTemplateId': ?sourceTemplateId,
      'assignedBy': ?assignedBy?.toMap(),
      'syncEnabled': ?syncEnabled,
    };
  }

  @override
  Map<String, dynamic> toDynamoItem() {
    return {
      'name': name,
      'exercises': exercises.map((ex) => ex.toDynamoItem()).toList(),
    }.toSnake();
  }

  @override
  TemplateItem copyWith({
    String? id,
    String? name,
    int? order,
    List<ExerciseItem>? exercises,
    String? sourceTemplateId,
    Profile? assignedBy,
  }) {
    return _TemplateItem(
      id: id ?? this.id,
      name: name ?? this.name,
      order: order ?? this.order,
      exercises: exercises ?? this.exercises,
      sourceTemplateId: sourceTemplateId ?? this.sourceTemplateId,
      assignedBy: assignedBy ?? this.assignedBy,
    );
  }
}

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

abstract interface class TemplateListResponse implements Model, Iterable<TemplateItem> {
  List<TemplateItem> get templates;

  String? get cursor;

  factory TemplateListResponse({
    required List<TemplateItem> templates,
    required String? cursor,
  }) = _TemplateListResponse;
}

class _TemplateListResponse with Iterable<TemplateItem> implements TemplateListResponse {
  @override
  final List<TemplateItem> templates;
  @override
  final String? cursor;

  const _TemplateListResponse({required this.templates, required this.cursor});

  @override
  Iterator<TemplateItem> get iterator => templates.iterator;

  @override
  Map<String, dynamic> toMap() {
    return {
      'templates': map((t) => t.toMap()).toList(),
      'cursor': ?cursor,
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
  Future<TemplateShareItem> shareTemplate({
    required String coachId,
    required String targetUserId,
    required String masterTemplateId,
  });

  Future<TemplateListResponse> getTemplates({required String userId, String? cursor, int? pageSize});

  Future<TemplateShareListResponse> getTemplateShares({required String userId, String? cursor, int? pageSize});
}
