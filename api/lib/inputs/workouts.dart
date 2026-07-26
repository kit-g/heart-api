part of 'inputs.dart';

/// Body for `PATCH /workouts/:workoutId` — a partial update of a workout's own
/// fields (name, start, end), leaving its exercises untouched. Every field is
/// optional but at least one must be present; an omitted field is left as-is.
///
/// Partial semantics come from omission: a field absent from the body isn't
/// changed. There's deliberately no way to *clear* a field here (e.g. blank the
/// name) — an empty/null `name` is rejected rather than treated as a clear.
class WorkoutPatchIn {
  final String? name;
  final DateTime? start;
  final DateTime? end;

  const WorkoutPatchIn._({this.name, this.start, this.end});

  static Future<WorkoutPatchIn> fromRequest(Request req) async {
    final json = await req.json();
    // `string` rejects empty/non-string, so a present `name` is always valid;
    // absence (not null) is what leaves it unchanged.
    final name = json.containsKey('name') ? json.string('name') : null;
    final start = json.dateOrNull('start');
    final end = json.dateOrNull('end');
    if (name == null && start == null && end == null) {
      throw const BadRequest(reason: 'provide at least one of name, start, end');
    }
    if (start != null && end != null && end.isBefore(start)) {
      throw const BadRequest(reason: 'end must not be before start');
    }
    return WorkoutPatchIn._(name: name, start: start, end: end);
  }
}
