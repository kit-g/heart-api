import 'dart:collection';
import 'dart:math';
import 'dart:typed_data';

import 'package:heart_models/heart_models.dart';

/// A collection of sets of the same exercise performed during a single workout
/// E.g., squats 4x10
abstract interface class WorkoutExercise
    with Iterable<ExerciseSet>, HasUuid
    implements Model, Completes, Comparable<WorkoutExercise> {
  String get id;

  Iterable<ExerciseSet> get sets;

  Exercise get exercise;

  double? get total;

  int? get order;

  set order(int? v);

  void add(ExerciseSet set);

  bool remove(ExerciseSet set);

  ExerciseSet? get best;

  /// whether at least one set was marked as done
  bool get isStarted;

  factory WorkoutExercise({required ExerciseSet starter}) {
    return _WorkoutExercise._(
      id: uuidV7(),
      starter: starter,
      exercise: starter.exercise,
    );
  }

  factory WorkoutExercise.fromJson(Map json) {
    final exercise = Exercise.fromJson(json['exercise']);
    return _WorkoutExercise._(
      exercise: exercise,
      sets: switch (json['sets']) {
        List l => l.map((e) => ExerciseSet.fromJson(exercise, e)).toList(),
        _ => [],
      },
      id: json['id'],
      order: json['exercise_order'] ?? json['order'],
    );
  }
}

abstract interface class HasExercises {
  /// starts a new exercise
  WorkoutExercise add(Exercise exercise);

  /// removes the [WorkoutExercise] from the workout
  bool remove(WorkoutExercise exercise);

  /// places [toInsert] before [before]
  /// and moves all other exercises by 1.
  void swap(WorkoutExercise toInsert, WorkoutExercise before);

  /// adds an exercise to the end of the workout
  void append(WorkoutExercise exercise);
}

/// A full workout
abstract interface class Workout with Iterable<WorkoutExercise>, HasUuid implements HasExercises, Model {
  String get id;

  DateTime get start;

  abstract String? name;

  abstract DateTime? end;

  Iterable<WorkoutExercise> get sets;

  Map<String, WorkoutImage>? get images;

  factory Workout({String? name}) {
    return _Workout._(
      id: uuidV7(),
      start: DateTime.timestamp(),
      name: name,
    );
  }

  factory Workout.fromExercises(Iterable<WorkoutExercise> exercises, {String? name}) {
    return _Workout._(
      id: uuidV7(),
      start: DateTime.timestamp(),
      name: name,
      exercises: exercises.toList(),
    );
  }

  factory Workout.fromRow(Map row, {required String Function(String) imageUrl}) {
    return _Workout._(
      id: row['id'],
      name: row['name'] as String,
      start: switch (row['started_at']) {
        DateTime dt => dt,
        String s when s.isNotEmpty => DateTime.parse(s),
        _ => throw ArgumentError(row['started_at']),
      },
      end: switch (row['completed_at']) {
        DateTime dt => dt,
        String s when s.isNotEmpty => DateTime.tryParse(s),
        _ => null,
      },
      exercises: switch (row['exercises']) {
        List l => l.map((e) => WorkoutExercise.fromJson(e)).toList(),
        _ => [],
      },
      images: switch (row['images']) {
        List l when l.isNotEmpty => {
          for (final e in l) (e as Map)['id'].toString(): WorkoutImage.fromRow(imageUrl(e['key'].toString()), e),
        },
        _ => null,
      },
    );
  }

  factory Workout.fromJson(Map json) = _Workout.fromJson;

  /// the total metric (e.g., weight)
  /// in all sets of this exercise
  double? get total;

  /// marks the workout as complete
  void finish(DateTime end);

  /// whether the workout was marked as complete
  bool get isCompleted;

  /// how long it lasted from [start] to [end]
  Duration? get duration;

  /// whether the workout was actually started,
  /// i.e. at least one set was marked as done
  bool get isStarted;

  /// whether the workout is ready to be finished
  /// i.e. all selected sets are marked as complete
  bool get isValid;

  (WorkoutExercise, ExerciseSet)? nextIncomplete(WorkoutExercise exercise, ExerciseSet last);

  WorkoutSummary toSummary();

  /// Makes a copy of itself with a new set of IDs
  Workout copy({bool sameId});

  void completeAllSets();

  void removeEmptySets();

  void resolveName(String defaultValue);

  Duration elapsed();
}

class _WorkoutExercise with Iterable<ExerciseSet>, HasUuid implements WorkoutExercise {
  @override
  final String id;
  final List<ExerciseSet> _sets;
  final Exercise _exercise;
  final DateTime start;

  @override
  int? order;

  _WorkoutExercise._({
    ExerciseSet? starter,
    DateTime? start,
    required this.id,
    this.order,
    required Exercise exercise,
    List<ExerciseSet>? sets,
  }) : _exercise = exercise,
       start = start ?? DateTime.timestamp(),
       _sets = sets ?? [] {
    if (starter != null) {
      _sets.add(starter);
    }
  }

  @override
  void add(ExerciseSet set) {
    _sets.add(set);
  }

  @override
  Iterator<ExerciseSet> get iterator => _sets.iterator;

  @override
  bool remove(ExerciseSet set) {
    return _sets.remove(set);
  }

  @override
  Iterable<ExerciseSet> get sets => _sets;

  @override
  Exercise get exercise => _sets.firstOrNull?.exercise ?? _exercise;

  @override
  double? get total {
    try {
      return map((each) => each.total).reduce((a, b) => (a ?? 0) + (b ?? 0));
    } on StateError {
      return 0;
    }
  }

  @override
  String toString() {
    return '$runtimeType $_exercise';
  }

  @override
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'exercise': ?firstOrNull?.exercise.toMap(),
      'start': start.toIso8601String(),
      'sets': [
        for (final each in this) each.toMap(),
      ],
    };
  }

  @override
  ExerciseSet? get best {
    try {
      return reduce((one, two) => one >= two ? one : two);
    } on StateError {
      return null;
    }
  }

  @override
  bool get isStarted => any((set) => set.isCompleted);

  @override
  int compareTo(WorkoutExercise other) {
    return switch ((other.order, order)) {
      ((int there, int here)) => here.compareTo(there),
      _ => other.id.compareTo(id),
    };
  }

  @override
  bool get isCompleted => every((set) => set.isCompleted);
}

abstract interface class WorkoutImage implements Comparable<WorkoutImage>, Media, Storable {
  String get workoutId;

  String get key;

  factory WorkoutImage.fromJson(Map json) = _WorkoutImage.fromJson;

  factory WorkoutImage.local(String url, String workoutId, Uint8List bytes) {
    final Uri(:String path) = Uri.parse(url);
    return _WorkoutImage(
      workoutId: workoutId,
      // https://<domain>/workouts/<hashed_id>/<image_id>.<ext>
      id: path.split('/').last.split('.').first,
      link: url,
      key: path,
      bytes: bytes,
    );
  }

  factory WorkoutImage.fromRow(String url, Map row) {
    final Uri(:String path) = Uri.parse(url);
    return _WorkoutImage(
      workoutId: row['workout_id'],
      // https://<domain>/workouts/<hashed_id>/<image_id>.<ext>
      id: row['id'],
      link: url,
      key: path,
    );
  }
}

class _WorkoutImage implements WorkoutImage {
  @override
  final String workoutId;
  @override
  final String id;
  @override
  final String link;
  @override
  final String key;
  @override
  final Uint8List? bytes;

  const _WorkoutImage({
    required this.workoutId,
    required this.id,
    required this.link,
    required this.key,
    this.bytes,
  });

  factory _WorkoutImage.fromJson(Map json) {
    return _WorkoutImage(
      workoutId: json['workoutId'],
      id: json['id'],
      link: json['url'],
      key: json['key'],
    );
  }

  @override
  Map<String, dynamic> toRow() {
    return {
      'workoutId': workoutId,
      'id': id,
      'url': link,
      'key': key,
    };
  }

  @override
  int compareTo(WorkoutImage other) {
    return other.id.compareTo(id);
  }

  @override
  bool operator ==(Object other) {
    return other is WorkoutImage && key == other.key;
  }

  @override
  int get hashCode => key.hashCode;

  @override
  String toString() {
    return 'Image $id';
  }

  @override
  DateTime? get timestamp => DateTime.tryParse(workoutId);
}

class _Workout with Iterable<WorkoutExercise>, HasUuid implements Workout {
  final List<WorkoutExercise> _sets;
  @override
  final DateTime start;
  @override
  final String id;
  @override
  String? name;
  @override
  final SplayTreeMap<String, WorkoutImage> images;

  @override
  DateTime? end;

  _Workout._({
    required this.start,
    this.name,
    required this.id,
    List<WorkoutExercise>? exercises,
    this.end,
    Map<String, WorkoutImage>? images,
  }) : _sets = exercises ?? <WorkoutExercise>[],
       images = SplayTreeMap.from(images ?? {});

  factory _Workout.fromJson(Map json) {
    return _Workout._(
      start: DateTime.parse(json['start']),
      name: json['name'],
      id: json['id'],
      end: DateTime.tryParse(json['end'] ?? ''),
      exercises: switch (json['exercises']) {
        List l => l.map((each) => WorkoutExercise.fromJson(each)).toList(),
        _ => null,
      },
      images: switch (json) {
        {'images': List l} when l.isNotEmpty => SplayTreeMap<String, WorkoutImage>.fromIterables(
          l.map<String>((each) => each['id']),
          l.map<WorkoutImage>((each) => WorkoutImage.fromJson(each)),
        ),
        _ => null,
      },
    );
  }

  @override
  void finish(DateTime end) {
    this.end = end;
  }

  @override
  Iterable<WorkoutExercise> get sets => _sets;

  @override
  bool remove(WorkoutExercise exercise) {
    return _sets.remove(exercise);
  }

  @override
  Iterator<WorkoutExercise> get iterator => _sets.iterator;

  @override
  Map<String, dynamic> toMap() {
    Map<String, dynamic> asRequest((int, WorkoutExercise) record) {
      return {'order': record.$1, ...record.$2.toMap()};
    }

    return {
      'id': id,
      'name': name,
      'start': start.toIso8601String(),
      'end': end?.toIso8601String(),
      'exercises': where((ex) => ex.isNotEmpty).indexed.map(asRequest).toList(),
      'images': images.values.map((img) => img.toRow()).toList(),
    };
  }

  @override
  String toString() {
    return switch (name) {
      String n => n,
      null => 'Workout on ${_dateFormat(start)}',
    };
  }

  static String _dateFormat(DateTime d) {
    return '${d.year}-${_pad(d.month)}-${_pad(d.day)}';
  }

  static String _pad(int i) {
    return i.toString().padLeft(2, '0');
  }

  @override
  WorkoutExercise add(Exercise exercise) {
    final ex = WorkoutExercise(starter: ExerciseSet(exercise));
    _sets.add(ex);
    return ex;
  }

  @override
  double? get total {
    try {
      return map((each) => each.total).reduce((a, b) => (a ?? 0) + (b ?? 0));
    } on StateError {
      return null;
    }
  }

  @override
  void swap(WorkoutExercise toInsert, WorkoutExercise before) {
    final toInsertIndex = _sets.indexOf(toInsert);
    final beforeIndex = _sets.indexOf(before);
    final descending = beforeIndex > toInsertIndex;
    final newIndex = descending ? max(beforeIndex - 1, 0) : beforeIndex;

    _sets
      ..remove(toInsert)
      ..insert(newIndex, toInsert);
  }

  @override
  void append(WorkoutExercise exercise) {
    _sets
      ..remove(exercise)
      ..add(exercise);
  }

  @override
  bool get isCompleted => end != null;

  @override
  Duration? get duration {
    return switch (end) {
      DateTime end => end.difference(start),
      null => null,
    };
  }

  @override
  bool get isStarted => any((exercise) => exercise.isStarted);

  @override
  bool get isValid => isStarted && every((exercise) => exercise.isCompleted);

  @override
  (WorkoutExercise, ExerciseSet)? nextIncomplete(WorkoutExercise exercise, ExerciseSet last) {
    return switch (exercise._nextIncomplete(last)) {
      ExerciseSet set => (exercise, set),
      _ => switch (_nextIncomplete(exercise)) {
        WorkoutExercise next => (next, next.first),
        _ => null,
      },
    };
  }

  @override
  WorkoutSummary toSummary() {
    return WorkoutSummary(
      id: id,
      name: name,
    );
  }

  @override
  Workout copy({bool sameId = false}) {
    final workout = _Workout._(
      id: sameId ? id : uuidV7(),
      name: name,
      start: sameId ? start : DateTime.timestamp(),
      images: images,
    );

    for (final each in this) {
      if (each.isNotEmpty) {
        final exercise = WorkoutExercise(starter: each.first.copy());

        for (final (index, set) in each.skip(1).indexed) {
          final start = DateTime.timestamp().add(Duration(milliseconds: 2 * index));
          exercise.add(set.copy(start: start));
        }

        workout.append(exercise);
      }
    }

    if (end case DateTime dt) {
      workout.finish(dt);
    }

    return workout;
  }

  @override
  void completeAllSets() {
    for (final each in this) {
      for (final set in each) {
        set.isCompleted = true;
      }
    }
  }

  @override
  void removeEmptySets() {
    forEach((exercise) => exercise.where((set) => !set.isCompleted).toList().forEach(exercise.remove));
    where((exercise) => exercise.isEmpty).toList().forEach(remove);
  }

  @override
  void resolveName(String defaultValue) {
    if (name?.isEmpty ?? true) {
      name = defaultValue;
    }
  }

  @override
  Duration elapsed() => DateTime.now().difference(start);
}

extension on Iterable<Completes> {
  Completes? _nextIncomplete(Completes element) {
    try {
      final l = toList();
      return l.sublist(l.indexOf(element)).firstWhere((each) => !each.isCompleted);
    } on StateError {
      return null;
    }
  }
}

abstract interface class ProgressGalleryResponse implements Iterable<WorkoutImage> {
  List<WorkoutImage> get images;

  String? get cursor;

  factory ProgressGalleryResponse({required List<WorkoutImage> images, String? cursor}) {
    return _ProgressGalleryResponse._(images: images, cursor: cursor);
  }

  factory ProgressGalleryResponse.fromJson(Map json) = _ProgressGalleryResponse.fromJson;
}

class _ProgressGalleryResponse with Iterable<WorkoutImage> implements ProgressGalleryResponse {
  @override
  final List<WorkoutImage> images;
  @override
  final String? cursor;

  const _ProgressGalleryResponse._({required this.images, this.cursor});

  const _ProgressGalleryResponse({
    required this.images,
    required this.cursor,
  });

  factory _ProgressGalleryResponse.fromJson(Map json) {
    return _ProgressGalleryResponse(
      images: switch (json) {
        {'images': List images} => images.map((each) => WorkoutImage.fromJson(each)).toList(),
        _ => [],
      },
      cursor: json['cursor'],
    );
  }

  @override
  Iterator<WorkoutImage> get iterator => images.iterator;
}

abstract interface class WorkoutResponse implements Model, Iterable<Workout> {
  List<Workout> get workouts;

  String? get cursor;

  factory WorkoutResponse({
    required final List<Workout> workouts,
    required final String? cursor,
  }) = _WorkoutResponse.new;
}

class _WorkoutResponse with Iterable<Workout> implements WorkoutResponse {
  @override
  final List<Workout> workouts;
  @override
  final String? cursor;

  const _WorkoutResponse({
    required this.workouts,
    required this.cursor,
  });

  @override
  Iterator<Workout> get iterator => workouts.iterator;

  @override
  Map<String, dynamic> toMap() {
    return {
      'workouts': map((w) => w.toMap()).toList(),
      'cursor': cursor,
    };
  }
}
