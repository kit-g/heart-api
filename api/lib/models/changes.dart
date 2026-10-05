import 'dart:convert';

import 'package:heart_models/heart_models.dart';

import 'errors.dart';

/// A position in a workout change feed: the time of the last change seen and
/// the id it belonged to. Opaque to callers, who only pass it back.
///
/// The one documented exception to "the cursor is the last item's id": a
/// feed is ordered by when things changed, and an id alone can't say that.
class ChangeCursor {
  final DateTime at;
  final String id;

  const new({required this.at, required this.id});

  /// Parses a cursor from a previous page. Anything that isn't one is the
  /// caller's mistake, never a fresh start.
  factory parse(String raw) {
    try {
      final decoded = utf8.decode(base64Url.decode(base64Url.normalize(raw)));
      final [at, id] = decoded.split('|');
      if (!isUuidV7(id)) throw const FormatException();
      return ChangeCursor(at: DateTime.parse(at).toUtc(), id: id);
    } catch (_) {
      throw BadRequest(reason: 'since is not a cursor from this feed: $raw');
    }
  }

  @override
  String toString() => base64Url.encode(utf8.encode('${at.toUtc().toIso8601String()}|$id')).replaceAll('=', '');
}

/// One page of a workout change feed: the workouts that changed (whole, as
/// they stand now) and the ids of those deleted, since a cursor.
class WorkoutChanges {
  final List<Workout> upserted;
  final List<({String id, DateTime deletedAt})> deleted;

  /// Where the next poll starts. Null only when the feed has never had
  /// anything to report, which is the same as starting from the beginning.
  final ChangeCursor? cursor;

  /// True when this page was cut short: ask again straight away.
  final bool hasMore;

  const new({required this.upserted, required this.deleted, required this.cursor, required this.hasMore});
}

/// One exercise's completed working sets, oldest first, ready for
/// [foldRecords].
typedef ExerciseRecordSets = ({String exerciseId, String name, Category category, List<RecordSet> sets});
