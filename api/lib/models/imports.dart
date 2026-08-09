import 'dart:convert';

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
  final String source;
  final List<ImportedWorkout> workouts;

  /// Data rows that failed to parse and were left out of the batch.
  final int rowsSkipped;

  WorkoutImport._({required this.source, required this.workouts, required this.rowsSkipped});

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
  factory WorkoutImport.fromStrongCsv(
    String csv, {
    MeasurementUnit unit = MeasurementUnit.metric,
    Duration utcOffset = Duration.zero,
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
            importId: 'strong:$rawDate#${name ?? ''}',
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
        builder.exercise(exercise).add(set);
      } on FormatException {
        skipped++;
      }
    }
    return WorkoutImport._(
      source: 'strong',
      workouts: [for (final b in builders.values) b.build()],
      rowsSkipped: skipped,
    );
  }
}

class ImportedWorkout {
  final String importId;
  final String? name;
  final DateTime start;
  final DateTime? end;
  final List<ImportedExercise> exercises;

  const ImportedWorkout({
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

  const ImportedExercise({required this.name, required this.sets});
}

class ImportedSet {
  final double? weight;
  final int? reps;
  final int? duration;
  final double? distance;

  const ImportedSet({this.weight, this.reps, this.duration, this.distance});

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
  final int exercisesMatched;

  /// Names that had no catalog or custom counterpart and were created as the
  /// user's custom exercises — the candidates for promoting into the shared
  /// library.
  final List<String> exercisesCreated;
  final int rowsSkipped;

  const WorkoutImportReport({
    required this.source,
    required this.workoutsFound,
    required this.workoutsCreated,
    required this.setsCreated,
    required this.exercisesMatched,
    required this.exercisesCreated,
    required this.rowsSkipped,
  });

  int get workoutsSkipped => workoutsFound - workoutsCreated;

  factory WorkoutImportReport.fromRow(Map<String, dynamic> row, {required String source, required int rowsSkipped}) {
    return WorkoutImportReport(
      source: source,
      workoutsFound: row['workouts_found'],
      workoutsCreated: row['workouts_created'],
      setsCreated: row['sets_created'],
      exercisesMatched: row['exercises_matched'],
      exercisesCreated: (row['exercises_created'] as List).cast<String>(),
      rowsSkipped: rowsSkipped,
    );
  }

  @override
  Map<String, dynamic> toMap() {
    return {
      'source': source,
      'workoutsFound': workoutsFound,
      'workoutsCreated': workoutsCreated,
      'workoutsSkipped': workoutsSkipped,
      'setsCreated': setsCreated,
      'exercisesMatched': exercisesMatched,
      'exercisesCreated': exercisesCreated,
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

  _WorkoutBuilder({required this.importId, required this.name, required this.start, required this.end});

  List<ImportedSet> exercise(String name) => _exercises.putIfAbsent(name, () => []);

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
