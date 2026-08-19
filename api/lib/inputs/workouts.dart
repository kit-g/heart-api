part of 'inputs.dart';

/// Body for `PATCH /workouts/:workoutId` — a partial update of a workout's own
/// fields (name, start, end, calories), leaving its exercises untouched. Every
/// field is optional but at least one must be present; an omitted field is left
/// as-is.
///
/// Partial semantics come from omission: a field absent from the body isn't
/// changed. There's deliberately no way to *clear* a field here (e.g. blank the
/// name) — an empty/null `name` is rejected rather than treated as a clear.
///
/// `calories` exists on PATCH because wearable energy totals settle after the
/// workout is saved: HealthKit delivers the final active-energy figure minutes
/// later, and the device patches it in once known.
/// `POST /workouts/imports?source=strong` — a Strong CSV export, parsed and
/// unit-normalized here so the route layer only ever sees the canonical
/// [WorkoutImport] batch.
///
/// Two body shapes:
/// - raw CSV (`text/csv` or anything non-JSON): the one-shot import — every
///   unmatched exercise name is created as the user's custom.
/// - JSON envelope `{"csv": "...", "createCustom": ["name", ...]}`: the
///   commit half of a preview→commit flow. `createCustom` is the allowlist of
///   unmatched names the user approved; absent means approve all, present
///   (even empty) means exactly those and no others.
///
/// Query params:
/// - `source` (required): the exporting app; only `strong` so far.
/// - `dryRun` (optional, default `false`): parse and resolve only — write
///   nothing, respond with the would-be report.
/// - `unit` (optional, `metric`|`imperial`, default `metric`): fallback for
///   exports that carry no unit columns of their own.
/// - `tzOffset` (optional, `±HH:MM`): the exporting device's UTC offset —
///   Strong timestamps are naive local time.
class ImportWorkoutsIn {
  final WorkoutImport batch;
  final bool dryRun;
  final List<String>? createCustom;

  const new _(this.batch, {required this.dryRun, this.createCustom});

  static Future<ImportWorkoutsIn> fromRequest(Request req) async {
    final q = req.url.queryParameters;
    final source = q.string('source');
    if (source != 'strong') {
      throw BadRequest(reason: 'unsupported source: $source (supported: strong)');
    }
    final dryRun = q.boolean('dryRun');
    final unit = switch (q.stringOrNull('unit')) {
      null => MeasurementUnit.metric,
      _ => q.parsed('unit', MeasurementUnit.fromString),
    };
    final offset = switch (q.stringOrNull('tzOffset')) {
      null => Duration.zero,
      _ => q.parsed('tzOffset', _tzOffset),
    };
    final (csv, createCustom) = await _body(req);
    try {
      return ImportWorkoutsIn._(
        WorkoutImport.fromStrongCsv(csv, unit: unit, utcOffset: offset),
        dryRun: dryRun,
        createCustom: createCustom,
      );
    } on FormatException catch (e) {
      throw BadRequest(reason: 'not a readable Strong export: ${e.message}');
    }
  }

  static Future<(String, List<String>?)> _body(Request req) async {
    if (req.body.bodyType?.mimeType != MimeType.json) return (await req.text(), null);
    final json = await req.json();
    final createCustom = switch (json['createCustom']) {
      null => null,
      List l when l.every((e) => e is String) => l.cast<String>(),
      _ => throw const BadRequest(reason: 'createCustom must be a list of strings'),
    };
    return (json.string('csv'), createCustom);
  }

  static Duration _tzOffset(String raw) {
    final match = RegExp(r'^([+-])(\d{2}):(\d{2})$').firstMatch(raw);
    if (match == null) throw const FormatException();
    final offset = Duration(hours: int.parse(match.group(2)!), minutes: int.parse(match.group(3)!));
    return match.group(1) == '-' ? -offset : offset;
  }
}

class WorkoutPatchIn {
  final String? name;
  final DateTime? start;
  final DateTime? end;
  final double? calories;

  const new _({this.name, this.start, this.end, this.calories});

  static Future<WorkoutPatchIn> fromRequest(Request req) async {
    final json = await req.json();
    // `string` rejects empty/non-string, so a present `name` is always valid;
    // absence (not null) is what leaves it unchanged.
    final name = json.containsKey('name') ? json.string('name') : null;
    final start = json.dateOrNull('start');
    final end = json.dateOrNull('end');
    final calories = switch (json['calories']) {
      null => null,
      num n when n >= 0 => n.toDouble(),
      _ => throw const BadRequest(reason: 'calories must be a non-negative number'),
    };
    if (name == null && start == null && end == null && calories == null) {
      throw const BadRequest(reason: 'provide at least one of name, start, end, calories');
    }
    if (start != null && end != null && end.isBefore(start)) {
      throw const BadRequest(reason: 'end must not be before start');
    }
    return WorkoutPatchIn._(name: name, start: start, end: end, calories: calories);
  }
}
