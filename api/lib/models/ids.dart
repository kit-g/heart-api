import 'package:heart_models/heart_models.dart';

import 'errors.dart';

/// Shared by both the `inputs/` layer (eager validation in `fromRequest`) and
/// [WorkoutRequest] (a lazy getter over its raw body) — the one place that
/// knows what a client-minted id looks like on the wire.
extension UuidV7Field on Map<String, dynamic> {
  /// Optional client-minted id (heart-api#66, the upsync replay): the app
  /// mints a v7 uuid at construction and it round-trips here so a retried
  /// create lands on the same row; absent, the server mints one instead.
  /// Present-but-malformed is the client's mistake, same rule everywhere this
  /// is used — `exercises`, `workouts`, `templates`, `template-folders`,
  /// `goals`.
  String? uuidV7OrNull([String field = 'id']) {
    return switch (this[field]) {
      null => null,
      final String id when isUuidV7(id) => id,
      _ => throw BadRequest(reason: '$field must be a UUIDv7'),
    };
  }
}
