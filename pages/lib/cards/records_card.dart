import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';

import 'format.dart';
import 'kit.dart';
import 'units.dart';

/// `get_personal_records`' card: per exercise, each record with the date it
/// was set and what it beat, then its rep maxes and lifetime totals.
///
/// The headline records come in the order the app lists them, each formatted
/// from its own fields, in the user's units (`unitSystem`). Like every card,
/// it has no browser imports and reads the result tolerantly.
class RecordsCard extends StatelessComponent {
  const new(this.records, this.format, {super.key});

  final Map<String, Object?> records;
  final Format format;

  Units get _units => Units.of(records['unitSystem']);

  @override
  Component build(BuildContext context) {
    final entries = records.maps('records');
    if (entries.isEmpty) return const p(classes: 'note', [.text('No records yet.')]);
    return div([
      for (final entry in entries) _exercise(entry),
      if (records['cursor'] != null) const p(classes: 'note', [.text('More exercises follow on the next page.')]),
      ?warningsOf(records['warnings']),
    ]);
  }

  /// Each kind: its key and label, the record's own value, and, where the
  /// value alone doesn't say it, the set that made it.
  List<_Kind> get _kinds => [
    (key: 'heaviest', label: 'Heaviest', best: (r) => r.toSetText(format, _units), set: null),
    (key: 'oneRepMax', label: 'Estimated 1RM', best: (r) => _kg(r, 'value'), set: (r) => r.toSetText(format, _units)),
    (
      key: 'bestVolume',
      label: 'Best set volume',
      best: (r) => _kg(r, 'value', round: true),
      set: (r) => r.toSetText(format, _units),
    ),
    (key: 'mostReps', label: 'Most reps', best: _mostReps, set: null),
    (key: 'lightestAssistance', label: 'Lightest assistance', best: (r) => r.toSetText(format, _units), set: null),
    (key: 'longestDistance', label: 'Longest distance', best: _km, set: _distanceSet),
    (key: 'longestDuration', label: 'Longest', best: (r) => r.number('seconds')?.toClock() ?? '—', set: null),
    (key: 'bestPace', label: 'Best pace', best: _pace, set: (r) => r.toSetText(format, _units)),
  ];

  Component _exercise(Map<String, Object?> entry) {
    final meta = [
      if (entry.number('sessions') case final sessions?) plural(sessions, 'session'),
      if (entry.text('lastTrained') case final last?) 'last trained ${format.date(last)}',
    ];
    final totals = [
      if (entry.number('totalVolume') case final volume?) '${format.weight(volume, _units, 0)} volume',
      if (entry.number('totalReps') case final reps?) '${format.number(reps, 0)} reps',
      if (entry.number('totalDistance') case final distance?) format.distance(distance, _units),
      if (entry.number('totalDuration') case final duration?) duration.toSpan(),
    ];
    return section(classes: 'card', [
      h1(classes: 'title', [.text(entry.object('exercise')?.text('name') ?? 'Exercise')]),
      if (meta.isNotEmpty) div(classes: 'muted', [.text(meta.join(' · '))]),
      const div(classes: 'rule', []),
      for (final (:key, :label, :best, :set) in _kinds)
        if (entry.object(key) case final record?)
          _record(
            label,
            best(record),
            set: set?.call(record),
            at: record.text('at'),
            was: switch (record.object('previous')) {
              final previous? => best(previous),
              null => null,
            },
          ),
      for (final max in entry.maps('repMaxes'))
        if ((max.number('reps'), max.number('weightKg')) case (final reps?, final weight?))
          _record('$reps-rep max', format.weight(weight, _units), at: max.text('at')),
      if (totals.isNotEmpty) p(classes: 'note', [.text('In all: ${totals.join(' · ')}')]),
    ]);
  }

  Component _record(String label, String best, {String? set, String? at, String? was}) {
    final line = [
      if (at != null) format.date(at),
      if (set != null && set.isNotEmpty) set,
      if (was != null) 'was $was',
    ].join(' · ');
    return div(classes: 'record', [
      span(classes: 'what', [.text(label)]),
      span(classes: 'best', [.text(best)]),
      if (line.isNotEmpty) span(classes: 'when', [.text(line)]),
    ]);
  }

  String _kg(Map<String, Object?> record, String key, {bool round = false}) {
    return switch (record.number(key)) {
      final n? => format.weight(n, _units, round ? 0 : 1),
      null => '—',
    };
  }

  String _km(Map<String, Object?> record) {
    return switch (record.number('distanceKm')) {
      final km? => format.distance(km, _units),
      null => '—',
    };
  }

  String _pace(Map<String, Object?> record) {
    return switch (record.number('pace')) {
      final pace? => format.pace(pace, _units),
      null => '—',
    };
  }

  String _mostReps(Map<String, Object?> record) {
    return [
      if (record.number('reps') case final reps?) '$reps reps',
      if (record.number('weightKg') case final weight?) format.weight(weight, _units),
    ].join(' · ');
  }

  String _distanceSet(Map<String, Object?> record) {
    return [
      if (record.number('weightKg') case final weight?) format.weight(weight, _units),
      if (record.number('seconds') case final seconds?) seconds.toClock(),
    ].join(' · ');
  }
}

typedef _Kind = ({
  String key,
  String label,
  String Function(Map<String, Object?> record) best,
  String Function(Map<String, Object?> record)? set,
});
