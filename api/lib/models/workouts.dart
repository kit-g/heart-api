import 'dart:convert';

import 'package:heart_models/heart_models.dart';

import 'errors.dart';
import 'ids.dart';
import 'imports.dart';
import 'sets.dart';

abstract interface class ApiWorkoutService {
  Future<Page<Workout>> getWorkouts({
    required String userId,
    required String targetUserId,
    required String Function(String) imageUrl,
    String? cursor,
    int limit,
  });

  Future<Workout> getWorkout({
    required String userId,
    required String workoutId,
    required String Function(String) imageUrl,
  });

  Future<Workout> getTargetWorkout({
    required String requesterId,
    required String targetUserId,
    required String workoutId,
    required String Function(String) imageUrl,
  });

  /// `created` is true when this call minted the row; false when [body]'s
  /// [WorkoutRequest.id] already named a workout the caller owns — the
  /// upsync replay's idempotent-retry case (heart-api#66) — in which
  /// case the existing row is returned untouched, content ignored.
  Future<(Workout, bool created)> createWorkout({
    required String userId,
    required WorkoutRequest body,
    required String Function(String) imageUrl,
  });

  Future<Workout> updateWorkout({
    required String userId,
    required String workoutId,
    required WorkoutRequest body,
    required String Function(String) imageUrl,
  });

  /// Partial update of a workout the user owns — sets only the provided fields
  /// (name/start/end/calories/note/pauses), leaving its exercises intact. A
  /// null argument leaves that field unchanged; [note] is a record so that
  /// `(value: null)` can clear the note. Null [pauses] keeps the stored ones,
  /// cut to the start and end the patch leaves.
  Future<Workout> patchWorkout({
    required String userId,
    required String workoutId,
    required String Function(String) imageUrl,
    String? name,
    DateTime? start,
    DateTime? end,
    double? calories,
    ({String? value})? note,
    List<WorkoutPause>? pauses,
  });

  Future<void> deleteWorkout({
    required String userId,
    required String workoutId,
  });

  /// Bulk-writes a parsed CSV export in one shot: resolves or creates the
  /// exercises it references, then inserts the workouts that aren't already
  /// imported (matched on their deterministic import id, so re-runs never
  /// duplicate). Workouts already imported are only enriched — a note, a set
  /// type, an RPE filled in where none is stored, nothing overwritten — and
  /// each exercise's rest timer becomes the user's preference where they have
  /// none.
  ///
  /// [createCustom] is the user's consent decision from the preview: the
  /// unmatched names to create as their custom exercises. Null means create
  /// all (the legacy, no-preview flow); declined names have their sets
  /// skipped and counted in the report.
  Future<WorkoutImportReport> importWorkouts({
    required String userId,
    required WorkoutImport batch,
    List<String>? createCustom,
  });

  /// The read-only half of a two-phase import: what [importWorkouts] would
  /// do with [batch] — how many workouts are new vs already imported, and
  /// which exercise names would need creating — without writing anything.
  Future<WorkoutImportPreview> previewImport({
    required String userId,
    required WorkoutImport batch,
  });
}

class WorkoutRequest {
  final String userId;
  final Map<String, dynamic> body;

  const new({
    required this.userId,
    required this.body,
  });

  DateTime? _dt(dynamic value) => switch (value) {
    String s => DateTime.tryParse(s),
    DateTime dt => dt,
    _ => null,
  };

  /// The workout's own client-minted id (heart-api#66) — absent, the
  /// insert mints one; present-but-malformed is the client's mistake, same
  /// rule as every other id on this payload.
  String? get id => body.uuidV7OrNull();

  /// Whether this payload speaks about the workout's children at all.
  ///
  /// `_replaceWorkout` deletes every `workout_exercise` and `exercise_set`
  /// before re-inserting, so a payload that simply doesn't mention `exercises`
  /// used to empty the workout — a shallow PUT (an image step, a summary
  /// re-save, a serializer that dropped detail) silently destroyed the
  /// session's whole body. The client already draws this distinction on its own
  /// mirror (heart-of-yours#85: a copy arriving without exercises keeps the
  /// ones it has); the server now draws it too.
  ///
  /// A JSON array — including `[]` — is the caller asserting contents, and an
  /// empty one legitimately empties the workout: the user took every set out.
  /// Absent or null is the caller saying nothing, and the children survive.
  bool get replacesExercises => body['exercises'] is List;

  /// Whether this payload speaks about the workout's note. The key is newer
  /// than most clients, so a replace leaves the stored note alone when it is
  /// absent; an explicit null or a blank string clears it.
  bool get setsNote => body.containsKey('note');

  /// Whether this payload speaks about the workout's pauses, by the same
  /// rule: absent keeps what is stored (cut to the new start and end), and a
  /// present list, an empty one included, is the new value.
  bool get setsPauses => body.containsKey('pauses');

  List<Map> _exercises() {
    final source = (body['exercises'] as List? ?? []).cast<Map>();
    final out = <Map>[];
    // A replace updates the rows it names in place, so an id named twice
    // would have one entry win and the other's sets vanish without an error;
    // it is refused up front instead.
    final ids = <String>{};
    // sets find their exercise by its order, so a repeated order would hang
    // one exercise's sets under both
    final orders = <Object?>{};
    void unique(String? id, String at) {
      if (id != null && !ids.add(id)) {
        throw BadRequest(code: 'duplicate_id', reason: '$at.id appears more than once in the payload');
      }
    }

    for (final (index, ex) in source.indexed) {
      // An emptied editor row names nothing *and* logged nothing — dropped,
      // the way the template path drops its own. Sets with no exercise to hang
      // them on is a different thing: that is a malformed client, and it falls
      // through to the 400 below. Dropping those silently made a bad payload
      // indistinguishable from `exercises: []`, so a malformed replace emptied
      // a healthy workout instead of being rejected.
      if (_isEmptyExercise(ex)) continue;
      out.add({
        // The reference is the exercise's uuid — the name is localized
        // display copy and resolves nothing since the id cutover. A present
        // but malformed reference is the client's mistake: a 400, not a
        // silent drop.
        'exercise_id': switch (ex['exercise']) {
          final String id when isUuidV7(id) => id,
          {'id': final String id} when isUuidV7(id) => id,
          _ => throw BadRequest(reason: 'exercises[$index].exercise must reference an exercise by its id'),
        },
        // A v7 id round-trips so a save keeps the row's identity — the
        // clients read an act's start off the id's mint instant, and a
        // re-minted id silently moves every act to "edited just now".
        // Anything else (absent, Firebase-era, garbage) is dropped and
        // the insert mints from 'start' instead.
        'id': ?_v7OrNull(ex['id']),
        'start': ?_dt(ex['start'])?.toIso8601String(),
        'order': ex['order'],
        'met': ?ex['met'],
        'note': ?_note(ex['note']),
        'sets': [
          for (final (setIndex, set) in (ex['sets'] as List? ?? []).cast<Map>().indexed)
            _set(set, at: 'exercises[$index].sets[$setIndex]'),
        ],
      });
      if (!orders.add(out.last['order'])) {
        throw BadRequest(
          code: 'duplicate_order',
          reason: 'exercises[$index].order appears more than once in the payload',
        );
      }
      unique(out.last['id'] as String?, 'exercises[$index]');
      for (final (setIndex, set) in (out.last['sets'] as List).cast<Map>().indexed) {
        unique(set['id'] as String?, 'exercises[$index].sets[$setIndex]');
      }
    }
    return out;
  }

  /// An editor row the user emptied: nothing names an exercise and nothing was
  /// logged against it. `WorkoutExercise.toMap()` writes `exercise` null-aware
  /// off its first set, so an emptied row serializes as `{id, start, sets: []}`
  /// with no `exercise` at all — and an entry that *does* carry sets always
  /// names one. Mirrors `isEmptyExercise` on the template input.
  static bool _isEmptyExercise(Map ex) {
    final hasSets = switch (ex['sets']) {
      final List l => l.isNotEmpty,
      _ => false,
    };
    return ex['exercise'] == null && !hasSets;
  }

  /// The same id round-trip for a set: keep a v7, strip anything else so the
  /// insert can cast-or-mint without tripping on a legacy id.
  ///
  /// `set_type` and `rpe` are newer than most clients, so their *absence* is
  /// meaningful: a replace keeps what is stored for a set whose payload leaves
  /// the key out (a client that doesn't know the field), while an explicit
  /// null clears it. Present values are checked here, so a bad one is a 400
  /// naming the set rather than a raw CHECK violation.
  static Map _set(Map set, {required String at}) {
    final copy = {...set}..remove('id');
    if (_v7OrNull(set['id']) case String id) {
      copy['id'] = id;
    }
    if (set.containsKey('set_type')) {
      copy['set_type'] = setType(set['set_type'], at: at).value;
    }
    if (set.containsKey('rpe')) {
      copy['rpe'] = switch (set['rpe']) {
        null => null,
        final num rpe when isRpe(rpe) => rpe,
        _ => throw BadRequest(code: 'invalid_rpe', reason: '$at.rpe must be 1-10 in half steps, or null'),
      };
    }
    return copy;
  }

  static String? _v7OrNull(Object? value) {
    return switch (value) {
      String id when isUuidV7(id) => id,
      _ => null,
    };
  }

  /// Normalises a per-exercise note: trims, treats blank as absent (a cleared pin
  /// is no pin), and caps the length so it stays a pin, not an essay — comments
  /// are the place for prose. Over-long is a clean 400, not a raw DB CHECK error.
  static String? _note(Object? value) => _boundedNote(value, maxExerciseNoteLength, 'an exercise note');

  /// The workout's own note, by the same rules as an exercise's with a longer
  /// bound; shared with `PATCH`.
  static String? workoutNote(Object? value) => _boundedNote(value, Workout.maxNoteLength, 'a workout note');

  static String? _boundedNote(Object? value, int max, String what) {
    return switch (value) {
      null => null,
      final String note when note.trim().isEmpty => null,
      // counted in code points, as the column counts them
      final String note when note.trim().runes.length <= max => note.trim(),
      final String _ => throw BadRequest(code: 'workout_note_too_long', reason: '$what is at most $max characters'),
      _ => throw BadRequest(reason: '$what must be a string'),
    };
  }

  /// The workout's pauses, closed and sorted by start; null is none. Each pause
  /// must end after it starts and none may overlap the next, so a bad one is a
  /// 400 naming it. Whether they fit the workout's own start and end is the
  /// column's CHECK, since a `PATCH` may leave either as stored.
  static List<WorkoutPause> workoutPauses(Object? value) {
    final source = switch (value) {
      null => const [],
      final List l when l.length <= Workout.maxPauses => l,
      final List _ => throw const BadRequest(
        code: 'invalid_pauses',
        reason: 'a workout has at most ${Workout.maxPauses} pauses',
      ),
      _ => throw const BadRequest(code: 'invalid_pauses', reason: 'pauses must be a list'),
    };
    WorkoutPause pause(int index, Object? each) {
      final (start, end) = switch (each) {
        {'start': final String start, 'end': final String end} => (DateTime.tryParse(start), DateTime.tryParse(end)),
        _ => (null, null),
      };
      return switch ((start, end)) {
        (final DateTime start, final DateTime end) when start.isBefore(end) => WorkoutPause(start: start, end: end),
        (DateTime _, DateTime _) => throw BadRequest(
          code: 'invalid_pauses',
          reason: 'pauses[$index] must end after it starts',
        ),
        _ => throw BadRequest(code: 'invalid_pauses', reason: 'pauses[$index] needs ISO-8601 start and end'),
      };
    }

    final pauses = [for (final (index, each) in source.indexed) (index, pause(index, each))]
      ..sort((a, b) => a.$2.start.compareTo(b.$2.start));
    for (var i = 1; i < pauses.length; i++) {
      final (index, next) = pauses[i];
      if (next.start.isBefore(pauses[i - 1].$2.end)) {
        throw BadRequest(code: 'invalid_pauses', reason: 'pauses[$index] overlaps another pause');
      }
    }
    return [for (final (_, pause) in pauses) pause];
  }

  /// Deliberately omits [id] — `_replaceWorkout` (unlike `_saveWorkout`) has
  /// no `@id` placeholder, and the postgres client rejects a superfluous named
  /// parameter, so a create merges `id` in itself rather than carrying it here.
  Map<String, dynamic> toParams() {
    return {
      'userId': userId,
      'name': body['name'],
      'startedAt': _dt(body['start']),
      'completedAt': _dt(body['end']),
      'calories': (body['calories'] as num?)?.toDouble(),
      'note': workoutNote(body['note']),
      'pauses': jsonEncode(workoutPauses(body['pauses']).map((pause) => pause.toMap()).toList()),
      'exercises': jsonEncode(_exercises()),
    };
  }
}
