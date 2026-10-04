import 'package:heart_models/heart_models.dart';

/// Formats a whole account can be exported in. Wire values are the names.
enum ExportFormat {
  strong;

  factory fromString(String v) {
    return values.firstWhere(
      (f) => f.name == v,
      orElse: () => throw ArgumentError.value(v, 'format', 'unknown export format'),
    );
  }

  String get mimeType => 'text/csv';

  String get extension => 'csv';
}

/// Strong's CSV export, column for column, so anything that reads one (Strong
/// switchers' next app, or Heart's own importer) reads this.
///
/// Strong writes measurements in the exporting user's units without saying
/// which, and local wall-clock times. This writes [unit]'s units and UTC
/// times, which is what Heart knows for certain. One row per completed set;
/// a workout with none has nothing to write.
String strongCsv(Iterable<Workout> workouts, {MeasurementUnit unit = .metric}) {
  final out = StringBuffer(_header.join(','))..write('\n');
  final imperial = unit == .imperial;

  for (final workout in workouts) {
    final start = workout.start.toUtc();
    final date = _date(start);
    final duration = switch (workout.end) {
      final DateTime end when end.isAfter(start) => _duration(end.difference(start)),
      _ => '',
    };

    for (final exercise in workout) {
      final sets = exercise.where((set) => set.isCompleted).toList();
      var working = 0;
      for (final (index, set) in sets.indexed) {
        final order = switch (set.setType) {
          .warmup => 'W',
          .drop => 'D',
          .failure => 'F',
          .normal => '${++working}',
        };
        final weight = switch (set.weight) {
          final double kg => _number(imperial ? kg.asPounds : kg),
          null => '',
        };
        final distance = switch (set.distance) {
          final double km => _number(imperial ? km.asMiles : km),
          null => '',
        };
        out
          ..write(
            [
              date,
              _quoted(workout.name ?? ''),
              duration,
              _quoted(exercise.exercise.name),
              order,
              weight,
              set.reps?.toString() ?? '',
              distance,
              set.duration?.toString() ?? '',
              index == 0 ? _quoted(exercise.note ?? '') : '',
              _quoted(workout.note ?? ''),
              switch (set.rpe) {
                final double rpe => _number(rpe),
                null => '',
              },
            ].join(','),
          )
          ..write('\n');
      }
    }
  }
  return out.toString();
}

const _header = [
  'Date',
  'Workout Name',
  'Duration',
  'Exercise Name',
  'Set Order',
  'Weight',
  'Reps',
  'Distance',
  'Seconds',
  'Notes',
  'Workout Notes',
  'RPE',
];

String _date(DateTime d) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${d.year}-${two(d.month)}-${two(d.day)} ${two(d.hour)}:${two(d.minute)}:${two(d.second)}';
}

/// Strong's own spelling: `19min`, `1h 3m`.
String _duration(Duration d) {
  final hours = d.inHours;
  final minutes = d.inMinutes.remainder(60);
  return hours == 0 ? '${minutes}min' : '${hours}h ${minutes}m';
}

/// Up to two decimals, without trailing zeros.
String _number(double v) {
  final fixed = v.toStringAsFixed(2);
  return fixed.contains('.') ? fixed.replaceFirst(RegExp(r'\.?0+$'), '') : fixed;
}

String _quoted(String s) => s.isEmpty ? '' : '"${s.replaceAll('"', '""')}"';

/// Where an export too large to answer inline is written, and the short-lived
/// link it's handed out by.
abstract interface class ExportStorage {
  /// Stores [bytes] under [key] and returns a presigned link to download them.
  Future<Uri> stash({required String key, required List<int> bytes, required String mimeType});
}
