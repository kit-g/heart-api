import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:heart_models/heart_models.dart';

/// Bulk workout import from another app's CSV export.
///
/// The parser turns a one-row-per-set export into the canonical
/// workout/exercise/set shape; the DB layer writes it in a single statement.
/// Each workout carries a deterministic [ImportedWorkout.importId] derived
/// from the source row, so re-running the same export is a no-op rather than
/// a duplicate history.

/// A parsed, unit-normalized import batch, ready for the DB layer.
///
/// Measurements are canonical metric (kg, km, seconds) regardless of the
/// export's display unit — matching what the client stores.
class WorkoutImport {
  /// Hard cap per import: a bigger export keeps only its most recent
  /// workouts by start time. Guards the single-statement DB write (and the
  /// server's memory) against an arbitrarily large or maliciously infinite
  /// file; a decade of daily training is ~3.7k workouts, so a real export
  /// never comes close.
  static const maxWorkouts = 10000;

  /// Hard cap on sets in a single workout. The gateway's body limit already
  /// bounds a request, but ~10MB of minimal rows all naming the same workout
  /// is still ~150k sets aimed at one row; a real workout tops out around a
  /// hundred. The extra rows are dropped and counted, and the DB enforces its
  /// own ceiling (1000/workout) behind this for every write path.
  static const maxSetsPerWorkout = 500;

  final String source;
  final List<ImportedWorkout> workouts;

  /// Data rows that failed to parse and were left out of the batch.
  final int rowsSkipped;

  /// Workouts beyond [maxWorkouts], dropped oldest-first.
  final int workoutsDropped;

  /// Sets beyond [maxSetsPerWorkout] in their workout, dropped in file order.
  final int setsDropped;

  new _({
    required this.source,
    required this.workouts,
    required this.rowsSkipped,
    required this.workoutsDropped,
    required this.setsDropped,
  });

  /// Distinct exercise names across the batch, each with a category/target
  /// guess for the ones that turn out not to exist and need to be created as
  /// the user's custom exercises.
  List<Map<String, String>> get exercises {
    final shapes = <String, ({bool weight, bool distance, bool seconds})>{};
    for (final workout in workouts) {
      for (final exercise in workout.exercises) {
        final prior = shapes[exercise.name] ?? (weight: false, distance: false, seconds: false);
        shapes[exercise.name] = (
          weight: prior.weight || exercise.sets.any((s) => s.weight != null),
          distance: prior.distance || exercise.sets.any((s) => s.distance != null),
          seconds: prior.seconds || exercise.sets.any((s) => s.duration != null),
        );
      }
    }
    return [
      for (final MapEntry(key: name, value: shape) in shapes.entries)
        {'name': name, 'category': _category(name, shape), 'target': 'Other'},
    ];
  }

  /// Set counts per exercise name across the batch — what a declined name
  /// would cost, surfaced in the preview so the user can decide informed.
  Map<String, int> get setsByExercise {
    final counts = <String, int>{};
    for (final workout in workouts) {
      for (final exercise in workout.exercises) {
        counts[exercise.name] = (counts[exercise.name] ?? 0) + exercise.sets.length;
      }
    }
    return counts;
  }

  int get setsFound => setsByExercise.values.fold(0, (total, n) => total + n);

  Map<String, dynamic> toParams({required String userId}) {
    return {
      'userId': userId,
      'workouts': jsonEncode([for (final w in workouts) w.toPayload()]),
      'exercises': jsonEncode(exercises),
    };
  }

  /// Parses a Strong CSV export (one row per set).
  ///
  /// Columns are matched by normalized header name, so the several column
  /// layouts Strong has shipped all parse: `Weight`+`Weight Unit`,
  /// `Weight (kg)`, `Distance (meters)`, `Workout Duration` vs `Duration`, and
  /// both `,` and `;` delimiters. [unit] is the fallback for exports that
  /// carry no unit information at all. Strong timestamps are naive local
  /// time; [utcOffset] is the exporting device's offset, applied to pin them
  /// to instants.
  ///
  /// Throws [FormatException] when the text isn't recognizable as a Strong
  /// export; individual bad rows are skipped and counted instead.
  factory fromStrongCsv(
    String csv, {
    MeasurementUnit unit = .metric,
    Duration utcOffset = .zero,
  }) {
    final delimiter = _detectDelimiter(csv);
    final rows = parseCsv(csv, delimiter: delimiter);
    if (rows.isEmpty) throw const FormatException('empty file');

    final header = [for (final cell in rows.first) _normalized(cell)];
    int? column(List<String> candidates) {
      for (final c in candidates) {
        final i = header.indexOf(c);
        if (i != -1) return i;
      }
      return null;
    }

    final date = column(['date']);
    final workoutName = column(['workoutname']);
    final exerciseName = column(['exercisename']);
    if (date == null || workoutName == null || exerciseName == null) {
      throw const FormatException('expected Strong columns: Date, Workout Name, Exercise Name');
    }
    final duration = column(['duration', 'workoutduration']);
    final weight = column(['weight', 'weightkg', 'weightlbs', 'weightlb']);
    final weightUnit = column(['weightunit']);
    final reps = column(['reps']);
    final distance = column(['distance', 'distancemeters', 'distancekm', 'distancemiles']);
    final distanceUnit = column(['distanceunit']);
    final seconds = column(['seconds']);

    // a unit spelled out in the header itself ("Weight (kg)") beats the fallback
    final headerWeightUnit = weight == null ? null : _unitIn(header[weight]);
    final headerDistanceUnit = distance == null ? null : _unitIn(header[distance]);

    String? cell(List<String> row, int? index) {
      if (index == null || index >= row.length) return null;
      final v = row[index].trim();
      return v.isEmpty ? null : v;
    }

    // Strong writes runaway durations with an unquoted thousands separator
    // ("3,527h 3min"), splitting the field and shifting the row; merging the
    // two pieces back restores the column alignment.
    List<String> repaired(List<String> row) {
      if (duration == null || row.length <= header.length) return row;
      final merged = '${row[duration]},${row[duration + 1]}';
      if (!RegExp(r'^\d{1,3}(,\d{3})+h( \d+(m|min))?$').hasMatch(merged)) return row;
      return [...row.sublist(0, duration), merged, ...row.sublist(duration + 2)];
    }

    var skipped = 0;
    var setsDropped = 0;
    final builders = <String, _WorkoutBuilder>{};
    for (final row in rows.skip(1).map(repaired)) {
      try {
        final rawDate = cell(row, date) ?? (throw const FormatException('no date'));
        final exercise = cell(row, exerciseName) ?? (throw const FormatException('no exercise'));
        final name = cell(row, workoutName);
        // parse the entire row before touching the builders, so a bad row
        // can't leave a half-built workout behind
        final set = ImportedSet(
          weight: _toKilograms(_number(cell(row, weight)), cell(row, weightUnit) ?? headerWeightUnit, unit),
          reps: _count(cell(row, reps)),
          duration: _count(cell(row, seconds)),
          distance: _toKilometers(_number(cell(row, distance)), cell(row, distanceUnit) ?? headerDistanceUnit, unit),
        );
        final builder = builders.putIfAbsent('$rawDate $name', () {
          final start = _instant(rawDate, utcOffset);
          return _WorkoutBuilder(
            importId: 'strong:${_opaque('$rawDate|${name ?? ''}')}',
            name: name,
            start: start,
            // a "duration" past 24h is a workout left running, not a window
            // worth storing
            end: switch (_parseDuration(cell(row, duration))) {
              Duration d when d > Duration.zero && d <= const Duration(hours: 24) => start.add(d),
              _ => null,
            },
          );
        });
        if (!builder.add(exercise, set)) setsDropped++;
      } on FormatException {
        skipped++;
      }
    }
    var workouts = [for (final b in builders.values) b.build()];
    var dropped = 0;
    if (workouts.length > maxWorkouts) {
      final byRecency = [...workouts]..sort((a, b) => b.start.compareTo(a.start));
      final kept = Set<ImportedWorkout>.identity()..addAll(byRecency.take(maxWorkouts));
      dropped = workouts.length - maxWorkouts;
      // filter rather than take the sorted list, preserving file order
      workouts = [
        for (final w in workouts)
          if (kept.contains(w)) w,
      ];
    }
    return WorkoutImport._(
      source: 'strong',
      workouts: workouts,
      rowsSkipped: skipped,
      workoutsDropped: dropped,
      setsDropped: setsDropped,
    );
  }
}

class ImportedWorkout {
  final String importId;
  final String? name;
  final DateTime start;
  final DateTime? end;
  final List<ImportedExercise> exercises;

  const new({
    required this.importId,
    required this.name,
    required this.start,
    required this.end,
    required this.exercises,
  });

  Map<String, dynamic> toPayload() {
    return {
      'importId': importId,
      'name': ?name,
      'start': start.toIso8601String(),
      'end': ?end?.toIso8601String(),
      'exercises': [
        for (final (order, exercise) in exercises.indexed)
          {
            'name': exercise.name,
            'order': order,
            'sets': [for (final set in exercise.sets) set.toPayload()],
          },
      ],
    };
  }
}

class ImportedExercise {
  final String name;
  final List<ImportedSet> sets;

  const new({required this.name, required this.sets});
}

class ImportedSet {
  final double? weight;
  final int? reps;
  final int? duration;
  final double? distance;

  const new({this.weight, this.reps, this.duration, this.distance});

  Map<String, dynamic> toPayload() {
    return {'weight': ?weight, 'reps': ?reps, 'duration': ?duration, 'distance': ?distance};
  }
}

/// What the import did, returned as the endpoint's response body.
class WorkoutImportReport implements Model {
  final String source;
  final int workoutsFound;
  final int workoutsCreated;
  final int setsCreated;

  /// Sets left out because the user declined their unmatched exercise —
  /// counted, never silently dropped. Excludes already-imported workouts.
  final int setsSkipped;
  final int exercisesMatched;

  /// Names that had no catalog or custom counterpart and were created as the
  /// user's custom exercises — the candidates for promoting into the shared
  /// library.
  final List<String> exercisesCreated;

  /// Unmatched names the user declined to create.
  final List<String> exercisesSkipped;
  final int rowsSkipped;

  /// Workouts beyond the per-import cap, dropped oldest-first at parse time.
  final int workoutsDropped;

  /// Sets beyond the per-workout cap, dropped in file order at parse time.
  final int setsDropped;

  const new({
    required this.source,
    required this.workoutsFound,
    required this.workoutsCreated,
    required this.setsCreated,
    required this.setsSkipped,
    required this.exercisesMatched,
    required this.exercisesCreated,
    required this.exercisesSkipped,
    required this.rowsSkipped,
    required this.workoutsDropped,
    required this.setsDropped,
  });

  int get workoutsSkipped => workoutsFound - workoutsCreated;

  factory fromRow(Map<String, dynamic> row, {required WorkoutImport batch}) {
    return WorkoutImportReport(
      source: batch.source,
      workoutsFound: row['workouts_found'],
      workoutsCreated: row['workouts_created'],
      setsCreated: row['sets_created'],
      setsSkipped: row['sets_skipped'],
      exercisesMatched: row['exercises_matched'],
      exercisesCreated: (row['exercises_created'] as List).cast<String>(),
      exercisesSkipped: (row['exercises_skipped'] as List).cast<String>(),
      rowsSkipped: batch.rowsSkipped,
      workoutsDropped: batch.workoutsDropped,
      setsDropped: batch.setsDropped,
    );
  }

  @override
  Map<String, dynamic> toMap() {
    return {
      'source': source,
      'workoutsFound': workoutsFound,
      'workoutsCreated': workoutsCreated,
      'workoutsSkipped': workoutsSkipped,
      'workoutsDropped': workoutsDropped,
      'setsCreated': setsCreated,
      'setsSkipped': setsSkipped,
      'setsDropped': setsDropped,
      'exercisesMatched': exercisesMatched,
      'exercisesCreated': exercisesCreated,
      'exercisesSkipped': exercisesSkipped,
      'rowsSkipped': rowsSkipped,
    };
  }
}

/// What an import *would* do — the `dryRun=true` response. Nothing is
/// written; the interesting half is [exercisesUnmatched], which the client
/// turns into the "bring these over as your own?" consent step.
class WorkoutImportPreview implements Model {
  final String source;
  final int workoutsFound;

  /// Workouts whose import identity is already in the user's history — a
  /// commit would skip these.
  final int workoutsAlreadyImported;
  final int setsFound;
  final int exercisesMatched;

  /// Unmatched names with what declining each would cost, in batch order.
  final List<({String name, int sets})> exercisesUnmatched;
  final int rowsSkipped;

  /// Workouts beyond the per-import cap, dropped oldest-first at parse time —
  /// surfaced here so the user learns *before* committing that only the most
  /// recent slice of an oversized file would import.
  final int workoutsDropped;

  /// Sets beyond the per-workout cap, dropped in file order at parse time.
  final int setsDropped;

  const new({
    required this.source,
    required this.workoutsFound,
    required this.workoutsAlreadyImported,
    required this.setsFound,
    required this.exercisesMatched,
    required this.exercisesUnmatched,
    required this.rowsSkipped,
    required this.workoutsDropped,
    required this.setsDropped,
  });

  /// Combines the resolve query's row (which names matched, which identities
  /// exist) with counts the parsed [batch] already knows.
  factory fromRow(Map<String, dynamic> row, {required WorkoutImport batch}) {
    final matched = ((row['exercises_matched'] as List).cast<String>()).toSet();
    return WorkoutImportPreview(
      source: batch.source,
      workoutsFound: batch.workouts.length,
      workoutsAlreadyImported: row['workouts_already_imported'],
      setsFound: batch.setsFound,
      exercisesMatched: matched.length,
      exercisesUnmatched: [
        for (final MapEntry(key: name, value: sets) in batch.setsByExercise.entries)
          if (!matched.contains(name)) (name: name, sets: sets),
      ],
      rowsSkipped: batch.rowsSkipped,
      workoutsDropped: batch.workoutsDropped,
      setsDropped: batch.setsDropped,
    );
  }

  @override
  Map<String, dynamic> toMap() {
    return {
      'source': source,
      'workoutsFound': workoutsFound,
      'workoutsAlreadyImported': workoutsAlreadyImported,
      'workoutsDropped': workoutsDropped,
      'setsFound': setsFound,
      'setsDropped': setsDropped,
      'exercisesMatched': exercisesMatched,
      'exercisesUnmatched': [
        for (final (:name, :sets) in exercisesUnmatched) {'name': name, 'sets': sets},
      ],
      'rowsSkipped': rowsSkipped,
    };
  }
}

/// Minimal RFC-4180 CSV: quoted fields, doubled-quote escapes, newlines
/// inside quotes, any of CRLF/LF/CR as row breaks. Fully-empty lines are
/// dropped.
List<List<String>> parseCsv(String text, {String delimiter = ','}) {
  final rows = <List<String>>[];
  var row = <String>[];
  final field = StringBuffer();
  var inQuotes = false;

  void endField() {
    row.add(field.toString());
    field.clear();
  }

  void endRow() {
    endField();
    if (row.length > 1 || row.first.isNotEmpty) rows.add(row);
    row = [];
  }

  for (var i = 0; i < text.length; i++) {
    final c = text[i];
    if (inQuotes) {
      if (c == '"') {
        if (i + 1 < text.length && text[i + 1] == '"') {
          field.write('"');
          i++;
        } else {
          inQuotes = false;
        }
      } else {
        field.write(c);
      }
    } else if (c == '"') {
      inQuotes = true;
    } else if (c == delimiter) {
      endField();
    } else if (c == '\r') {
      if (i + 1 < text.length && text[i + 1] == '\n') i++;
      endRow();
    } else if (c == '\n') {
      endRow();
    } else {
      field.write(c);
    }
  }
  if (field.isNotEmpty || row.isNotEmpty) endRow();
  return rows;
}

class _WorkoutBuilder {
  final String importId;
  final String? name;
  final DateTime start;
  final DateTime? end;
  final _exercises = <String, List<ImportedSet>>{};
  var _totalSets = 0;

  new({required this.importId, required this.name, required this.start, required this.end});

  /// Adds the set unless the workout is already at [WorkoutImport.maxSetsPerWorkout].
  bool add(String exercise, ImportedSet set) {
    if (_totalSets >= WorkoutImport.maxSetsPerWorkout) return false;
    _totalSets++;
    _exercises.putIfAbsent(exercise, () => []).add(set);
    return true;
  }

  ImportedWorkout build() {
    return ImportedWorkout(
      importId: importId,
      name: name,
      start: start,
      end: end,
      exercises: [
        for (final MapEntry(key: name, value: sets) in _exercises.entries) ImportedExercise(name: name, sets: sets),
      ],
    );
  }
}

String _detectDelimiter(String csv) {
  final firstLine = csv.split('\n').first;
  return !firstLine.contains(',') && firstLine.contains(';') ? ';' : ',';
}

/// Deterministic opaque token for an import identity: same source row →
/// same token, but nothing of the row (names, dates) survives into a value
/// that ends up in URLs and logs. 64 bits of sha256 — collision-free at any
/// realistic per-user history size.
String _opaque(String identity) => sha256.convert(utf8.encode(identity)).toString().substring(0, 16);

/// `"Workout Name"` → `workoutname`, `"Weight (kg)"` → `weightkg`
String _normalized(String header) => header.toLowerCase().replaceAll(RegExp('[^a-z]'), '');

/// A unit baked into a normalized header name: `weightkg` → `kg`.
String? _unitIn(String normalizedHeader) {
  for (final unit in const ['kg', 'lbs', 'lb', 'meters', 'km', 'miles']) {
    if (normalizedHeader.endsWith(unit)) return unit;
  }
  return null;
}

/// Strong timestamps are naive local time (`2023-01-15 17:35:12`); pins one
/// to an instant using the exporting device's [utcOffset].
DateTime _instant(String raw, Duration utcOffset) {
  final normalized = raw.trim().replaceFirst(' ', 'T');
  if (RegExp(r'(Z|[+-]\d{2}:?\d{2})$').hasMatch(normalized)) return DateTime.parse(normalized).toUtc();
  return DateTime.parse('${normalized}Z').subtract(utcOffset);
}

/// `1h 10m`, `47m`, `1h 5m 30s`, `1:10:00`, `70:00` — Strong has used all of
/// these for workout duration.
Duration? _parseDuration(String? raw) {
  // commas are thousands separators in runaway durations ("3,527h 3min")
  final t = raw?.trim().toLowerCase().replaceAll(',', '');
  if (t == null || t.isEmpty) return null;
  if (t.contains(':')) {
    final parts = t.split(':').map(int.tryParse).toList();
    return switch (parts) {
      [final int m, final int s] => Duration(minutes: m, seconds: s),
      [final int h, final int m, final int s] => Duration(hours: h, minutes: m, seconds: s),
      _ => null,
    };
  }
  final tokens = RegExp(r'(\d+)\s*(h|m|s)').allMatches(
    t.replaceAll('hours', 'h').replaceAll('hour', 'h').replaceAll('min', 'm').replaceAll('sec', 's'),
  );
  if (tokens.isEmpty) return null;
  var total = Duration.zero;
  for (final token in tokens) {
    final value = int.parse(token.group(1)!);
    total += switch (token.group(2)!) {
      'h' => Duration(hours: value),
      'm' => Duration(minutes: value),
      _ => Duration(seconds: value),
    };
  }
  return total;
}

/// Zero means "unset" in Strong exports, so it maps to null rather than a
/// stored zero. Tolerates a decimal comma from `;`-delimited locales.
double? _number(String? raw) {
  if (raw == null) return null;
  final parsed = double.tryParse(raw) ?? double.tryParse(raw.replaceAll(',', '.'));
  if (parsed == null) throw FormatException('not a number: $raw');
  return parsed == 0 ? null : parsed;
}

int? _count(String? raw) => _number(raw)?.round();

double? _toKilograms(double? value, String? unit, MeasurementUnit fallback) {
  if (value == null) return null;
  return switch (unit?.trim().toLowerCase()) {
    'kg' || 'kgs' || 'kilograms' => value,
    'lb' || 'lbs' || 'pounds' => value.asKilograms,
    _ => fallback == MeasurementUnit.imperial ? value.asKilograms : value,
  };
}

double? _toKilometers(double? value, String? unit, MeasurementUnit fallback) {
  if (value == null) return null;
  return switch (unit?.trim().toLowerCase()) {
    'km' || 'kilometers' => value,
    'meters' || 'm' => value / 1000,
    'miles' || 'mi' => value.asKilometers,
    _ => fallback == MeasurementUnit.imperial ? value.asKilometers : value,
  };
}

/// Best-effort category for an exercise we have to create: the equipment
/// modifier in the name when it maps cleanly, otherwise inferred from what
/// its sets actually record.
String _category(String name, ({bool weight, bool distance, bool seconds}) shape) {
  final n = name.toLowerCase();
  if (n.contains('(barbell)')) return 'Barbell';
  if (n.contains('(dumbbell)') || n.contains('(kettlebell)')) return 'Dumbbell';
  if (n.contains('(machine)') || n.contains('(cable)') || n.contains('(smith machine)')) return 'Machine';
  if (shape.distance) return 'Cardio';
  if (shape.seconds && !shape.weight) return 'Duration';
  if (shape.weight) return 'Weighted Body Weight';
  return 'Reps Only';
}
