import 'dart:math';

import 'auth.dart';
import 'exercise.dart';
import 'exercise_set.dart';
import 'misc.dart';
import 'template_folder.dart';
import 'uuid.dart';
import 'workout.dart';

abstract interface class Template
    with Iterable<WorkoutExercise>
    implements Comparable<Template>, HasExercises, Model, Storable {
  abstract String? name;

  bool get local;

  String get id;

  int get order;

  /// The folder the owner filed this under, or null when unfiled. Folders are
  /// flat, so this is the whole of a template's placement.
  ///
  /// Nested rather than a bare id so that rendering a list of templates needs no
  /// second request — the same call `assignedBy` makes. The nested copy has no
  /// [TemplateFolder.templateCount]; only `GET /template-folders` counts, and it
  /// is also the only way to see a folder that happens to be empty.
  TemplateFolder? get folder;

  /// Shorthand for `folder?.id` — the grouping key, and what a write sends back.
  String? get folderId;

  /// The coach's master template this one was copied from, when it arrived by
  /// assignment. Null for a template the owner wrote themselves.
  String? get sourceTemplateId;

  /// Who assigned this template, when it arrived by assignment. Null for the
  /// owner's own work — which is how the app tells the two apart.
  Profile? get assignedBy;

  /// Whether later edits to the master should flow down. Null on templates that
  /// were never assigned.
  bool? get syncEnabled;

  /// True when this template came from a coach rather than being written here.
  bool get isAssigned;

  /// When this template came to exist — recovered from the id, not stored.
  /// Server ids are v7 uuids minted by the same INSERT that stamps the row's
  /// `created_at`, so the embedded instant agrees with it to the millisecond;
  /// an assigned copy's id is minted at assignment, which is the copy's
  /// creation. Firebase-era ids were timestamps outright, hence the parse
  /// fallback. Null only for an id from neither era.
  DateTime? get createdAt;

  Workout toWorkout();

  /// An otherwise identical template filed under [folder] — null unfiles it.
  ///
  /// [folder] is deliberately required rather than defaulted: null is a
  /// meaningful value here (unfiled), so there is no "absent" for a default
  /// to mean. The exercises are carried into a fresh list, but the
  /// [WorkoutExercise] objects themselves are shared with the original.
  Template copyWith({required TemplateFolder? folder});

  factory empty({required String id, required int order, TemplateFolder? folder}) {
    return _Template(
      exercises: [],
      id: id,
      order: order,
      folder: folder,
      local: true,
    );
  }

  factory fromJson(Map json) {
    return _Template(
      exercises: switch (json['exercises']) {
        List l => l.map((each) => WorkoutExercise.fromJson(each)).toList(),
        _ => [],
      },
      id: json['id'].toString(),
      order: json['order'],
      name: json['name'],
      folder: switch (json['folder']) {
        final Map m => TemplateFolder.fromJson(m),
        _ => null,
      },
      sourceTemplateId: json['sourceTemplateId']?.toString(),
      assignedBy: switch (json['assignedBy']) {
        final Map m => Profile.fromJson(m),
        _ => null,
      },
      syncEnabled: json['syncEnabled'] as bool?,
      local: false,
    );
  }

  factory fromWorkout(String id, Workout workout, int order, {TemplateFolder? folder}) {
    return _Template(
      exercises: workout.toList(),
      id: id,
      order: order,
      name: workout.name,
      folder: folder,
      local: true,
    );
  }

  /// The folder arrives as the flat `folder_*` columns of the `LEFT JOIN` in
  /// `_listTemplates` and friends — null across the board when unfiled.
  factory fromRow(Map<String, dynamic> row) {
    return _Template(
      id: row['id'].toString(),
      name: row['name'] as String? ?? '',
      order: (row['order_index'] as num?)?.toInt() ?? 0,
      exercises: switch (row['exercises']) {
        List l => l.map((each) => WorkoutExercise.fromJson(each as Map)).toList(),
        _ => [],
      },
      local: false,
      folder: switch (row['folder_id']) {
        null => null,
        final id => TemplateFolder(
          id: id.toString(),
          name: row['folder_name'] as String? ?? '',
          order: (row['folder_order'] as num?)?.toInt() ?? 0,
          createdAt: row['folder_created_at'] as DateTime?,
        ),
      },
      sourceTemplateId: row['source_template_id']?.toString(),
      assignedBy: switch (row['assigned_by_id']) {
        final String id => Profile(
          id: id,
          name: row['assigned_by_username'] as String?,
          avatar: row['assigned_by_avatar'] as String?,
        ),
        _ => null,
      },
      syncEnabled: row['sync_enabled'] as bool?,
    );
  }
}

class _Template with Iterable<WorkoutExercise>, HasUuid implements Template {
  @override
  final String id;
  @override
  String? name;
  @override
  int order;
  @override
  final bool local;
  @override
  final TemplateFolder? folder;
  @override
  final String? sourceTemplateId;
  @override
  final Profile? assignedBy;
  @override
  final bool? syncEnabled;

  final List<WorkoutExercise> _exercises;

  new({
    required this._exercises,
    this.name,
    required this.id,
    required this.order,
    required this.local,
    this.folder,
    this.sourceTemplateId,
    this.assignedBy,
    this.syncEnabled,
  });

  @override
  String? get folderId => folder?.id;

  @override
  bool get isAssigned => assignedBy != null;

  @override
  DateTime? get createdAt => DateTime.tryParse(id) ?? timestampOfUuidV7(id);

  @override
  Iterator<WorkoutExercise> get iterator => _exercises.iterator;

  @override
  WorkoutExercise add(Exercise exercise) {
    final ex = WorkoutExercise(starter: ExerciseSet(exercise));
    _exercises.add(ex);
    return ex;
  }

  @override
  bool remove(WorkoutExercise exercise) {
    return _exercises.remove(exercise);
  }

  @override
  bool operator ==(Object other) {
    return other is Template && id == other.id;
  }

  @override
  int get hashCode => id.hashCode;

  @override
  int compareTo(Template other) {
    final orderComparison = order.compareTo(other.order);
    if (orderComparison != 0) {
      return orderComparison;
    }
    return id.compareTo(other.id);
  }

  @override
  Template copyWith({required TemplateFolder? folder}) {
    return _Template(
      exercises: List.of(_exercises),
      id: id,
      order: order,
      name: name,
      local: local,
      folder: folder,
      sourceTemplateId: sourceTemplateId,
      assignedBy: assignedBy,
      syncEnabled: syncEnabled,
    );
  }

  @override
  Workout toWorkout() {
    final exercises = <WorkoutExercise>[];
    for (final each in this) {
      if (each.isNotEmpty) {
        final exercise = WorkoutExercise(
          starter: each.first.copy(),
        );

        for (final set in each.skip(1)) {
          exercise.add(set.copy());
        }

        exercises.add(exercise);
      }
    }

    return Workout.fromExercises(exercises, name: name);
  }

  @override
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'order': order,
      'folder': ?folder?.toMap(),
      'sourceTemplateId': ?sourceTemplateId,
      'assignedBy': ?assignedBy?.toMap(),
      'syncEnabled': ?syncEnabled,
      'exercises': [
        for (final exercise in this) exercise.toMap(),
      ],
    };
  }

  /// Deliberately narrower than [toMap]: the app spreads this straight into a
  /// SQLite insert (`heart_db` `_Templates.storeTemplates`), so every key here
  /// must be a column in the app's local `templates` table. Adding one without
  /// an app-side migration breaks writes at runtime, not at compile time.
  @override
  Map<String, dynamic> toRow() {
    return {
      'id': id,
      'name': name,
      'order_in_parent': order,
    };
  }

  @override
  void swap(WorkoutExercise toInsert, WorkoutExercise before) {
    final toInsertIndex = _exercises.indexOf(toInsert);
    final beforeIndex = _exercises.indexOf(before);
    final descending = beforeIndex > toInsertIndex;
    final newIndex = descending ? max(beforeIndex - 1, 0) : beforeIndex;

    _exercises
      ..remove(toInsert)
      ..insert(newIndex, toInsert);
  }

  @override
  void append(WorkoutExercise exercise) {
    _exercises
      ..remove(exercise)
      ..add(exercise);
  }
}
