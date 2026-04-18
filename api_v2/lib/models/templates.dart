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

  bool get syncEnabled;

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
      syncEnabled: row['sync_enabled'] as bool? ?? true,
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
  final bool syncEnabled;

  const _TemplateItem({
    required this.id,
    required this.name,
    required this.order,
    required this.exercises,
    this.sourceTemplateId,
    this.assignedBy,
    this.syncEnabled = true,
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
      'sourceTemplateId': sourceTemplateId,
      'assignedBy': ?assignedBy?.toMap(),
      'syncEnabled': syncEnabled,
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
  String get studentId;

  String get studentTemplateId;

  DateTime get assignedAt;

  factory TemplateShareItem.fromRow(Map<String, dynamic> row) {
    final sk = row['SK'] as String;
    return _TemplateShareItem(
      studentId: sk.split('#').last, // TEMPLATE_SHARE#<templateId>#<studentId>
      studentTemplateId: row['studentTemplateId'] as String,
      assignedAt: DateTime.parse(row['assignedAt'] as String),
    );
  }
}

class _TemplateShareItem implements TemplateShareItem {
  @override
  final String studentId;
  @override
  final String studentTemplateId;
  @override
  final DateTime assignedAt;

  const _TemplateShareItem({
    required this.studentId,
    required this.studentTemplateId,
    required this.assignedAt,
  });

  @override
  Map<String, dynamic> toMap() {
    return {
      'studentId': studentId,
      'studentTemplateId': studentTemplateId,
      'assignedAt': assignedAt.toIso8601String(),
    };
  }
}

abstract interface class ApiTemplateService {
  Future<TemplateItem> shareTemplate({
    required String coachId,
    required String studentId,
    required String masterTemplateId,
  });
}
