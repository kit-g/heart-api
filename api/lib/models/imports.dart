import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:csv/csv.dart';
import 'package:heart_models/heart_models.dart';

import 'hevy_months.dart';
import 'sets.dart';

/// Bulk workout import from another app's CSV export.
///
/// The parser turns a one-row-per-set export into the canonical
/// workout/exercise/set shape; the DB layer writes it in a single statement.
/// Each workout carries a deterministic [ImportedWorkout.importId] derived
/// from the source row, so re-running the same export never duplicates a
/// history: a workout already imported is only enriched with what a richer
/// export adds (notes, set types, RPE), never rewritten.

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

  /// The longest rest timer taken from an export, in seconds; a longer one is
  /// a typo or a corrupt cell, not a rest anyone configured.
  static const maxRestTimer = 3600;

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

  /// The rest timer each exercise was last trained with, by exercise name —
  /// what the user's per-exercise timer preference becomes where they have
  /// none. Read off the most recent workout that ran a timer for the
  /// exercise: the most frequent value there, since a timer nudged mid-rest
  /// (±5/±15 s) leaves one-off values beside the configured one; a tie goes
  /// to the longer timer.
  ///
  /// Case-variant spellings are one exercise (the database resolves names
  /// case-insensitively), so they share one latest session.
  Map<String, int> get restTimers {
    final latest = <String, (String, DateTime, List<int>)>{};
    for (final workout in workouts) {
      for (final exercise in workout.exercises) {
        if (exercise.restTimers.isEmpty) continue;
        final key = exercise.name.toLowerCase();
        if (latest[key] case (_, final start, _) when !workout.start.isAfter(start)) continue;
        latest[key] = (exercise.name, workout.start, exercise.restTimers);
      }
    }
    return {
      for (final (name, _, timers) in latest.values) name: _mode(timers),
    };
  }

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
      'source': source,
      'workouts': jsonEncode([for (final w in workouts) w.toPayload()]),
      'exercises': jsonEncode(exercises),
      'restTimers': jsonEncode([
        for (final MapEntry(key: name, value: seconds) in restTimers.entries) {'name': name, 'seconds': seconds},
      ]),
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
    final rows = parseCsv(csv);
    if (rows.isEmpty) throw const FormatException('empty file');
    final header = _Header.of(rows.first);
    final column = header.column;

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
    final setOrder = column(['setorder']);
    final rpe = column(['rpe']);
    final notes = column(['notes']);
    final workoutNotes = column(['workoutnotes']);

    // a unit spelled out in the header itself ("Weight (kg)") beats the fallback
    final headerWeightUnit = weight == null ? null : _unitIn(header.names[weight]);
    final headerDistanceUnit = distance == null ? null : _unitIn(header.names[distance]);

    // Strong writes runaway durations with an unquoted thousands separator
    // ("3,527h 3min"), splitting the field and shifting the row; merging the
    // two pieces back restores the column alignment.
    List<String> repaired(List<String> row) {
      if (duration == null || row.length <= header.names.length) return row;
      final merged = '${row[duration]},${row[duration + 1]}';
      if (!RegExp(r'^\d{1,3}(,\d{3})+h( \d+(m|min))?$').hasMatch(merged)) return row;
      return [...row.sublist(0, duration), merged, ...row.sublist(duration + 2)];
    }

    var skipped = 0;
    var setsDropped = 0;
    final builders = <String, _WorkoutBuilder>{};
    // the set a "Rest Timer" row belongs to is the set row right before it —
    // read off the raw row, so a set that was skipped or capped still counts
    String? previousOrder;
    for (final row in rows.skip(1).map(repaired)) {
      // Strong interleaves non-set rows with the sets: after any set that
      // ran a rest timer comes a "Rest Timer" row, flagged in the Set Order
      // column — real sets carry a number there, or W/D/F for
      // warm-up/drop/failure. Structure, not a set: never counted like a bad
      // row, only read for the timer's length (in Seconds). Warm-ups run
      // Strong's separate warm-up timer, which is not the exercise's own.
      if (_cell(row, setOrder) case final order? when _normalized(order) == 'resttimer') {
        final builder = builders['${_cell(row, date)} ${_cell(row, workoutName)}'];
        final afterWarmUp = switch (previousOrder) {
          final String order => _strongSetType(order) == 'warmup',
          null => false,
        };
        if (_lenientNumber(_cell(row, seconds))?.round() case final timer?
            when builder != null && timer > 0 && timer <= maxRestTimer && !afterWarmUp) {
          builder.addRestTimer(_cell(row, exerciseName) ?? '', timer);
        }
        continue;
      }
      previousOrder = _cell(row, setOrder);
      try {
        final rawDate = _cell(row, date) ?? (throw const FormatException('no date'));
        final exercise = _cell(row, exerciseName) ?? (throw const FormatException('no exercise'));
        final name = _cell(row, workoutName);
        // parse the entire row before touching the builders, so a bad row
        // can't leave a half-built workout behind
        final set = ImportedSet(
          weight: _toKilograms(_number(_cell(row, weight)), _cell(row, weightUnit) ?? headerWeightUnit, unit),
          reps: _count(_cell(row, reps)),
          duration: _count(_cell(row, seconds)),
          distance: _toKilometers(_number(_cell(row, distance)), _cell(row, distanceUnit) ?? headerDistanceUnit, unit),
          type: switch (_cell(row, setOrder)) {
            final String order => _strongSetType(order),
            null => null,
          },
          rpe: _rpe(_cell(row, rpe)),
        );
        final builder = builders.putIfAbsent('$rawDate $name', () {
          final start = _instant(rawDate, utcOffset);
          return _WorkoutBuilder(
            importId: 'strong:${_opaque('$rawDate|${name ?? ''}')}',
            name: name,
            start: start,
            // a "duration" past 24h is a workout left running, not a window
            // worth storing
            end: switch (_parseDuration(_cell(row, duration))) {
              Duration d when d > Duration.zero && d <= const Duration(hours: 24) => start.add(d),
              _ => null,
            },
          );
        });
        builder.note ??= _cell(row, workoutNotes);
        if (!builder.add(exercise, set, note: _cell(row, notes))) setsDropped++;
      } on FormatException {
        skipped++;
      }
    }
    final (workouts, dropped) = _capped([for (final b in builders.values) b.build()]);
    return WorkoutImport._(
      source: 'strong',
      workouts: workouts,
      rowsSkipped: skipped,
      workoutsDropped: dropped,
      setsDropped: setsDropped,
    );
  }

  /// Parses a Hevy CSV export (one row per set).
  ///
  /// Hevy has two exporters with one column layout. The app
  /// (`workout_data.csv`) writes dates as `d MMM yyyy, HH:mm` with the month
  /// token in the app's language, translates catalog exercise titles into that
  /// language, escapes a line break inside a field as the two characters `\n`
  /// and mixes CRLF with bare LF row endings. The web (`workouts.csv`) writes
  /// `Intl`'s medium date in the browser's language and keeps every title in
  /// English. Both are naive local time at minute precision with no offset;
  /// [utcOffset] pins them. The app's dates parse in every language
  /// ([hevyMonths]); of the web's, only English does, and a file none of whose
  /// rows parse is refused whole (a [FormatException], like a file without the
  /// columns) rather than reported as every row skipped. Exercise titles are
  /// kept as the file writes them: the database resolves a translated catalog
  /// title to its English one, so the parser never needs Hevy's catalog.
  ///
  /// A workout is a contiguous run of rows with equal title, start, end and
  /// description. `title` + `start_time` does not identify one — two sessions
  /// can share both at minute precision — so the import id adds the end and
  /// the run's ordinal among equal keys. An exercise logged twice in one
  /// session stays two exercises, as the lifter had it. Hevy exports zero as
  /// blank, so blank is null; a set with nothing in it or a negative number is
  /// a skipped row. Supersets are not kept. Weight and distance columns name
  /// their unit (`weight_kg`/`weight_lbs`, `distance_km`/`distance_miles`);
  /// [unit] is the fallback for a bare header.
  ///
  /// Throws [FormatException] when the text isn't recognizable as a Hevy
  /// export; individual bad rows are skipped and counted instead.
  factory fromHevyCsv(
    String csv, {
    MeasurementUnit unit = .metric,
    Duration utcOffset = .zero,
  }) {
    final rows = parseCsv(csv);
    if (rows.isEmpty) throw const FormatException('empty file');
    final header = _Header.of(rows.first);
    final column = header.column;

    final title = column(['title']);
    final start = column(['starttime']);
    final end = column(['endtime']);
    final exerciseTitle = column(['exercisetitle']);
    if (title == null || start == null || exerciseTitle == null) {
      throw const FormatException('expected Hevy columns: title, start_time, exercise_title');
    }
    final description = column(['description']);
    final exerciseNotes = column(['exercisenotes']);
    final setIndex = column(['setindex']);
    final setType = column(['settype']);
    final weight = column(['weightkg', 'weightlbs', 'weight']);
    final reps = column(['reps']);
    final distance = column(['distancekm', 'distancemiles', 'distance']);
    final seconds = column(['durationseconds']);
    final rpe = column(['rpe']);
    final weightUnit = weight == null ? null : _unitIn(header.names[weight]);
    final distanceUnit = distance == null ? null : _unitIn(header.names[distance]);

    var skipped = 0;
    var setsDropped = 0;
    String? firstFailure;
    final builders = <_WorkoutBuilder>[];
    // how many runs have carried each identity so far: the ordinal that tells
    // two sessions with the same title, start and end apart
    final runs = <String, int>{};
    _WorkoutBuilder? current;
    List<String?>? currentKey;
    String? previousExercise;
    for (final row in rows.skip(1)) {
      try {
        final rawStart = _cell(row, start) ?? (throw const FormatException('no start_time'));
        final exercise = _cell(row, exerciseTitle) ?? (throw const FormatException('no exercise_title'));
        final key = [_cell(row, title), rawStart, _cell(row, end), _cell(row, description)];
        // parse the entire row before touching the builders, so a bad row
        // can't leave a half-built workout behind
        final set = ImportedSet(
          weight: _toKilograms(_nonNegative(_cell(row, weight)), weightUnit, unit),
          reps: _nonNegative(_cell(row, reps))?.round(),
          duration: _nonNegative(_cell(row, seconds))?.round(),
          distance: _toKilometers(_nonNegative(_cell(row, distance)), distanceUnit, unit),
          type: _hevySetType(_cell(row, setType)),
          rpe: _rpe(_cell(row, rpe)),
        );
        if (set.isEmpty) throw const FormatException('a set with nothing in it');
        if (current == null || !_sameKey(key, currentKey)) {
          final startLocal = _hevyLocal(rawStart);
          final endLocal = switch (_cell(row, end)) {
            final String raw => _hevyLocal(raw),
            null => null,
          };
          final name = _cell(row, title);
          final identity = '${_minute(startLocal)}|${endLocal == null ? '' : _minute(endLocal)}|${name ?? ''}';
          final run = runs[identity] = (runs[identity] ?? 0) + 1;
          current = _WorkoutBuilder(
            importId: 'hevy:${_opaque('$identity|$run')}',
            name: name,
            start: startLocal.subtract(utcOffset),
            // an end before the start, or past 24h, is a window not worth
            // storing, as with Strong
            end: switch (endLocal?.difference(startLocal)) {
              Duration d when d > Duration.zero && d <= const Duration(hours: 24) => endLocal!.subtract(utcOffset),
              _ => null,
            },
          )..note = _unescaped(_cell(row, description));
          currentKey = key;
          previousExercise = null;
          builders.add(current);
        }
        // set_index restarts at 0 for every exercise block, so a 0 after a run
        // of the same exercise is that exercise logged a second time
        final newBlock = exercise != previousExercise || _cell(row, setIndex) == '0';
        if (!current.add(exercise, set, note: _unescaped(_cell(row, exerciseNotes)), newBlock: newBlock)) {
          setsDropped++;
        }
        previousExercise = exercise;
      } on FormatException catch (e) {
        skipped++;
        firstFailure ??= e.message;
      }
    }
    // the layout is Hevy's but no row parsed: a date format this parser
    // doesn't read (a web export in another language), not a bad row
    if (builders.isEmpty && firstFailure != null) throw FormatException(firstFailure);
    final (workouts, dropped) = _capped([for (final b in builders) b.build()]);
    return WorkoutImport._(
      source: 'hevy',
      workouts: workouts,
      rowsSkipped: skipped,
      workoutsDropped: dropped,
      setsDropped: setsDropped,
    );
  }

  /// Keeps the most recent [maxWorkouts] by start time, in file order, and
  /// counts the rest.
  static (List<ImportedWorkout>, int) _capped(List<ImportedWorkout> workouts) {
    if (workouts.length <= maxWorkouts) return (workouts, 0);
    final byRecency = [...workouts]..sort((a, b) => b.start.compareTo(a.start));
    final kept = Set<ImportedWorkout>.identity()..addAll(byRecency.take(maxWorkouts));
    // filter rather than take the sorted list, preserving file order
    return (
      [
        for (final w in workouts)
          if (kept.contains(w)) w,
      ],
      workouts.length - maxWorkouts,
    );
  }
}

/// The apps whose exports the importer reads: the `source` query parameter's
/// vocabulary.
enum ImportSource {
  strong('Strong'),
  hevy('Hevy');

  /// The app's name as the user knows it, for error messages.
  final String label;

  new(this.label);

  /// Parses [csv] with this source's parser into the one canonical batch.
  WorkoutImport parse(String csv, {MeasurementUnit unit = .metric, Duration utcOffset = .zero}) {
    return switch (this) {
      .strong => WorkoutImport.fromStrongCsv(csv, unit: unit, utcOffset: utcOffset),
      .hevy => WorkoutImport.fromHevyCsv(csv, unit: unit, utcOffset: utcOffset),
    };
  }
}

/// Where an export no parser could read is kept until a person imports it.
abstract interface class ImportStorage {
  /// Keeps [bytes] as the user's parked [source] export; returns the object
  /// key, which is what the owner's alert points at.
  Future<String> park({required String userId, required ImportSource source, required List<int> bytes});
}

/// The `202` answer to an export the parser could not read: nothing was
/// imported, the file is kept, and the user will hear from a person once it
/// has been. [status] is the stable word a client branches on; [message] is
/// prose it may show as is.
class WorkoutImportParked implements Model {
  final ImportSource source;
  final String key;

  /// The parser's reason, for the owner's eyes as much as the user's.
  final String reason;

  const new({required this.source, required this.key, required this.reason});

  @override
  Map<String, dynamic> toMap() {
    return {
      'source': source.name,
      'status': 'parked',
      'message':
          "We couldn't read this ${source.label} export automatically. "
          "We've kept the file and will message you once it has been imported.",
      'reason': reason,
    };
  }
}

class ImportedWorkout {
  /// The longest note a workout keeps; the column's bound.
  static const maxNoteLength = Workout.maxNoteLength;

  final String importId;
  final String? name;
  final DateTime start;
  final DateTime? end;
  final String? note;
  final List<ImportedExercise> exercises;

  const new({
    required this.importId,
    required this.name,
    required this.start,
    required this.end,
    required this.exercises,
    this.note,
  });

  Map<String, dynamic> toPayload() {
    return {
      'importId': importId,
      'name': ?name,
      'start': start.toIso8601String(),
      'end': ?end?.toIso8601String(),
      'note': ?note,
      'exercises': [
        for (final (order, exercise) in exercises.indexed)
          {
            'name': exercise.name,
            'order': order,
            'note': ?exercise.note,
            'sets': [for (final set in exercise.sets) set.toPayload()],
          },
      ],
    };
  }
}

class ImportedExercise {
  static const maxNoteLength = maxExerciseNoteLength;

  final String name;
  final List<ImportedSet> sets;
  final String? note;

  /// Every rest timer run after a working set of this exercise in this
  /// workout, in file order; feeds [WorkoutImport.restTimers], never a set.
  final List<int> restTimers;

  const new({required this.name, required this.sets, this.note, this.restTimers = const []});
}

class ImportedSet {
  final double? weight;
  final int? reps;
  final int? duration;
  final double? distance;

  /// `warmup`, `drop` or `failure`; null for an ordinary working set,
  /// including when the export says nothing about it.
  final String? type;

  /// 1–10 in half steps; null when unrated or when the export's value is off
  /// that scale — the set itself still imports.
  final double? rpe;

  const new({this.weight, this.reps, this.duration, this.distance, this.type, this.rpe});

  /// No measurement at all — a row that records nothing.
  bool get isEmpty => weight == null && reps == null && duration == null && distance == null;

  Map<String, dynamic> toPayload() {
    return {
      'weight': ?weight,
      'reps': ?reps,
      'duration': ?duration,
      'distance': ?distance,
      'setType': ?type,
      'rpe': ?rpe,
    };
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

  /// Already-imported workouts this run filled a gap in (a note, a set's type
  /// or RPE) — no longer counted as skipped.
  final int workoutsEnriched;

  /// Existing sets that gained a type or an RPE.
  final int setsEnriched;

  /// Exercises whose rest timer preference the import set, where the user had
  /// none.
  final int restTimersSet;

  const new({
    required this.source,
    required this.workoutsFound,
    required this.workoutsCreated,
    required this.workoutsEnriched,
    required this.setsCreated,
    required this.setsEnriched,
    required this.restTimersSet,
    required this.setsSkipped,
    required this.exercisesMatched,
    required this.exercisesCreated,
    required this.exercisesSkipped,
    required this.rowsSkipped,
    required this.workoutsDropped,
    required this.setsDropped,
  });

  int get workoutsSkipped => workoutsFound - workoutsCreated - workoutsEnriched;

  factory fromRow(Map<String, dynamic> row, {required WorkoutImport batch}) {
    return WorkoutImportReport(
      source: batch.source,
      workoutsFound: row['workouts_found'],
      workoutsCreated: row['workouts_created'],
      workoutsEnriched: row['workouts_enriched'],
      setsCreated: row['sets_created'],
      setsEnriched: row['sets_enriched'],
      restTimersSet: row['rest_timers_set'],
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
      'workoutsEnriched': workoutsEnriched,
      'workoutsSkipped': workoutsSkipped,
      'workoutsDropped': workoutsDropped,
      'setsCreated': setsCreated,
      'setsEnriched': setsEnriched,
      'setsSkipped': setsSkipped,
      'setsDropped': setsDropped,
      'exercisesMatched': exercisesMatched,
      'exercisesCreated': exercisesCreated,
      'exercisesSkipped': exercisesSkipped,
      'restTimersSet': restTimersSet,
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
  /// commit creates none of these again.
  final int workoutsAlreadyImported;

  /// Of [workoutsAlreadyImported], the ones a commit would fill a gap in.
  final int workoutsEnriched;

  /// Existing sets a commit would give a type or an RPE.
  final int setsEnriched;

  /// Exercises a commit would set a rest timer preference for, counting every
  /// unmatched name as approved.
  final int restTimersSet;
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
    required this.workoutsEnriched,
    required this.setsEnriched,
    required this.restTimersSet,
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
      workoutsEnriched: row['workouts_enriched'],
      setsEnriched: row['sets_enriched'],
      restTimersSet: row['rest_timers_set'],
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
      'workoutsEnriched': workoutsEnriched,
      'workoutsDropped': workoutsDropped,
      'setsFound': setsFound,
      'setsEnriched': setsEnriched,
      'restTimersSet': restTimersSet,
      'setsDropped': setsDropped,
      'exercisesMatched': exercisesMatched,
      'exercisesUnmatched': [
        for (final (:name, :sets) in exercisesUnmatched) {'name': name, 'sets': sets},
      ],
      'rowsSkipped': rowsSkipped,
    };
  }
}

/// RFC-4180 CSV via `package:csv` — quoted fields, doubled-quote escapes,
/// newlines inside quotes, any of CRLF/LF/CR as row breaks, plus a BOM and
/// Excel `sep=` hints. Rows whose every field is empty are dropped. With
/// [delimiter] null, the delimiter is auto-detected over the first lines
/// (`,`, `;`, tab, `|`) — which is what recognizes both `,`- and
/// `;`-delimited Strong exports.
List<List<String>> parseCsv(String text, {String? delimiter}) {
  final rows = CsvDecoder(fieldDelimiter: delimiter).convert(text);
  return [
    for (final row in rows) [for (final cell in row) cell as String],
  ];
}

/// The CSV header, normalized, and the lookup every parser starts with.
class _Header {
  final List<String> names;

  new(this.names);

  factory of(List<String> raw) => _Header([for (final cell in raw) _normalized(cell)]);

  /// The index of the first of [candidates] present, in normalized form.
  int? column(List<String> candidates) {
    for (final c in candidates) {
      final i = names.indexOf(c);
      if (i != -1) return i;
    }
    return null;
  }
}

/// A row's cell by column index: null when the column is absent, short or
/// blank.
String? _cell(List<String> row, int? index) {
  if (index == null || index >= row.length) return null;
  final v = row[index].trim();
  return v.isEmpty ? null : v;
}

/// One exercise's run of sets within a workout.
class _ExerciseBlock {
  final String name;
  final sets = <ImportedSet>[];
  // insertion-ordered: a note repeated on several rows is kept once
  final notes = <String>{};
  final restTimers = <int>[];

  new(this.name);
}

class _WorkoutBuilder {
  final String importId;
  final String? name;
  final DateTime start;
  final DateTime? end;
  String? note;
  final _blocks = <_ExerciseBlock>[];
  var _totalSets = 0;

  new({required this.importId, required this.name, required this.start, required this.end});

  /// Adds the set unless the workout is already at
  /// [WorkoutImport.maxSetsPerWorkout]. With [newBlock] null the set joins the
  /// exercise's one block wherever it is (Strong lists an exercise once per
  /// workout); true opens a block even for a name already present, false
  /// continues the latest one (Hevy keeps an exercise's second appearance
  /// separate, as the lifter logged it).
  bool add(String exercise, ImportedSet set, {String? note, bool? newBlock}) {
    if (_totalSets >= WorkoutImport.maxSetsPerWorkout) return false;
    _totalSets++;
    final block = switch (newBlock) {
      null => _blocks.firstWhere((b) => b.name == exercise, orElse: () => _open(exercise)),
      true => _open(exercise),
      false => _blocks.last,
    };
    block.sets.add(set);
    if (note != null) block.notes.add(note);
    return true;
  }

  void addRestTimer(String exercise, int seconds) {
    _blocks.lastWhereOrNull((b) => b.name == exercise)?.restTimers.add(seconds);
  }

  _ExerciseBlock _open(String exercise) {
    final block = _ExerciseBlock(exercise);
    _blocks.add(block);
    return block;
  }

  ImportedWorkout build() {
    return ImportedWorkout(
      importId: importId,
      name: name,
      start: start,
      end: end,
      note: _bounded(note, ImportedWorkout.maxNoteLength),
      exercises: [
        for (final block in _blocks)
          ImportedExercise(
            name: block.name,
            sets: block.sets,
            note: _bounded(block.notes.isEmpty ? null : block.notes.join('\n'), ImportedExercise.maxNoteLength),
            restTimers: block.restTimers,
          ),
      ],
    );
  }
}

extension<T> on List<T> {
  T? lastWhereOrNull(bool Function(T) test) {
    for (final item in reversed) {
      if (test(item)) return item;
    }
    return null;
  }
}

/// Cuts [text] to [max] characters, counted the way the database counts them
/// (code points, so an emoji is never split in half).
String? _bounded(String? text, int max) {
  if (text == null) return null;
  final runes = text.runes;
  return runes.length <= max ? text : String.fromCharCodes(runes.take(max));
}

/// The most frequent value; among equally frequent ones, the largest.
int _mode(List<int> values) {
  final counts = <int, int>{};
  for (final v in values) {
    counts[v] = (counts[v] ?? 0) + 1;
  }
  return counts.entries.reduce((best, e) {
    final better = e.value > best.value || (e.value == best.value && e.key > best.key);
    return better ? e : best;
  }).key;
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

/// Two workout keys from consecutive rows: equal when the rows belong to one
/// contiguous run.
bool _sameKey(List<String?> a, List<String?>? b) {
  if (b == null || a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// A wall-clock minute as text: `2026-09-22T06:00`.
String _minute(DateTime local) => local.toIso8601String().substring(0, 16);

final _hevyAppDate = RegExp(r'^(\d{1,2}) (\S+) (\d{4}), (\d{1,2}):(\d{2})$');
final _hevyWebDate = RegExp(r'^([A-Za-z]+)\.? (\d{1,2}), (\d{4}), (\d{1,2}):(\d{2}) ([AP]M)$', caseSensitive: false);

/// A Hevy timestamp as the wall clock it shows, in a UTC [DateTime] that
/// stands in for naive local time: the app's `1 Sept. 2026, 07:30` in any
/// language, or the web's `Sep 1, 2026, 7:30 AM` in English.
DateTime _hevyLocal(String raw) {
  final text = raw.trim();
  if (_hevyAppDate.firstMatch(text) case final m?) {
    return _wallClock(
      raw,
      year: int.parse(m[3]!),
      month: _hevyMonth(m[2]!, raw),
      day: int.parse(m[1]!),
      hour: int.parse(m[4]!),
      minute: int.parse(m[5]!),
    );
  }
  if (_hevyWebDate.firstMatch(text) case final m?) {
    final pm = m[6]!.toUpperCase() == 'PM';
    return _wallClock(
      raw,
      year: int.parse(m[3]!),
      month: _hevyMonth(m[1]!, raw),
      day: int.parse(m[2]!),
      hour: int.parse(m[4]!) % 12 + (pm ? 12 : 0),
      minute: int.parse(m[5]!),
    );
  }
  throw FormatException('unreadable date "$raw": export from the Hevy app, or from hevy.com in English');
}

int _hevyMonth(String token, String raw) {
  return hevyMonths[token.toLowerCase().replaceFirst(RegExp(r'\.+$'), '')] ??
      (throw FormatException('unreadable month in "$raw"'));
}

/// [DateTime.utc] normalizes an impossible date (Feb 30) into a possible one;
/// an export never has one, so it's a misread, not a day.
DateTime _wallClock(
  String raw, {
  required int year,
  required int month,
  required int day,
  required int hour,
  required int minute,
}) {
  final local = DateTime.utc(year, month, day, hour, minute);
  if (local.day != day || local.hour != hour || local.minute != minute) {
    throw FormatException('impossible date "$raw"');
  }
  return local;
}

/// The Hevy app escapes a line break inside a field as the two characters
/// `\n` (a typed backslash-n is indistinguishable, and far rarer than a
/// multi-line note); the web keeps real CRLFs. Both come out as LF so the
/// same note reads the same from either exporter.
String? _unescaped(String? text) => text?.replaceAll(r'\n', '\n').replaceAll('\r\n', '\n');

/// `warmup`, `dropset`, `failure` or `normal`, in English whatever the
/// export's language.
String? _hevySetType(String? raw) {
  return switch (raw?.trim().toLowerCase()) {
    'warmup' => 'warmup',
    'dropset' => 'drop',
    'failure' => 'failure',
    _ => null,
  };
}

/// Like [_number], and a negative value — which no measurement is — costs the
/// row: the database would reject it, and silently dropping the sign would
/// invent a set.
double? _nonNegative(String? raw) {
  return switch (_number(raw)) {
    final double v when v < 0 => throw FormatException('negative measurement: $raw'),
    final v => v,
  };
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

/// A finite number, tolerating a decimal comma from `;`-delimited locales;
/// `NaN` and `Infinity` parse as doubles but are no measurement.
double? _parsed(String raw) {
  return switch (double.tryParse(raw) ?? double.tryParse(raw.replaceAll(',', '.'))) {
    final double v when v.isFinite => v,
    _ => null,
  };
}

/// Zero means "unset" in Strong exports, so it maps to null rather than a
/// stored zero.
double? _number(String? raw) {
  if (raw == null) return null;
  final parsed = _parsed(raw) ?? (throw FormatException('not a number: $raw'));
  return parsed == 0 ? null : parsed;
}

int? _count(String? raw) => _number(raw)?.round();

/// Like [_number] for a field whose garbage must not cost the whole row: an
/// unreadable value is simply absent.
double? _lenientNumber(String? raw) {
  if (raw == null) return null;
  final parsed = _parsed(raw);
  return parsed == 0 ? null : parsed;
}

/// RPE on its 1–10 scale in half steps. Anything else — a typo, a value
/// from a finer or different scale — is left out rather than guessed at or
/// allowed to reject the set it sits on.
double? _rpe(String? raw) {
  return switch (_lenientNumber(raw)) {
    final double v when isRpe(v) => v,
    _ => null,
  };
}

/// Strong's Set Order column: a number for a working set, a letter for the
/// other kinds. A working set, or anything unrecognised, is null — normal.
String? _strongSetType(String order) {
  return switch (order.trim().toUpperCase()) {
    'W' => 'warmup',
    'D' => 'drop',
    'F' => 'failure',
    _ => null,
  };
}

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
  if (shape.distance) return shape.weight ? 'Weighted Distance' : 'Cardio';
  if (shape.seconds) return shape.weight ? 'Weighted Duration' : 'Duration';
  if (shape.weight) return 'Weighted Body Weight';
  return 'Reps Only';
}
