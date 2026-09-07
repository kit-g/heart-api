import 'misc.dart';

/// One kind of row an account owns, and therefore one thing a data export has
/// to carry. The enum name is the wire key.
///
/// Ordered as the upsync replay orders its writes (`docs/2026-09-05.upsync-replay.md`
/// in `heart-api`) — references after the rows they point at — so a caller
/// walking [AccountSummary.collections] in order walks a valid dependency order
/// too.
///
/// Device registrations are deliberately absent: an FCM token is plumbing the
/// account happens to hold, not something a person exports.
enum ExportableCollection {
  customExercises,
  exercisePreferences,
  templateFolders,
  templates,
  templateShares,
  workouts,
  workoutImages,
  goals,
  comments,
  connections;

  /// The collection named [key], or `null` when this build has never heard of
  /// it. Unknown keys are skipped rather than thrown on: the app pulls this
  /// package from git `main` and can lag a server that has added a collection.
  static ExportableCollection? tryParse(String key) => values.asNameMap()[key];
}

/// How much of one [ExportableCollection] the server holds.
abstract interface class CollectionSummary implements Model {
  /// Rows the account owns in this collection.
  int get count;

  /// The newest row's id, or `null` when the collection is empty — and always
  /// `null` for [ExportableCollection.connections], whose rows are keyed by
  /// `(initiator, target, domain)` and have no id of their own.
  ///
  /// Ids are uuid v7, so this is both the newest row and the high-water mark: a
  /// mirror holding the same [count] but a different `latestId` has diverged,
  /// which the count alone reads as "in sync".
  String? get latestId;

  const factory({required int count, String? latestId}) = _CollectionSummary;

  factory fromJson(Map json) = _CollectionSummary.fromJson;
}

/// What the server holds for one account, per collection — the completeness
/// check behind the app's data export. The device compares each count (and,
/// where the collection has one, the newest id) against its local mirror and
/// knows whether it is about to export everything or only part of it.
///
/// Nothing health-derived appears here, and nothing can: the server stores no
/// health data at all (`CLAUDE.md`, *The device-only health rule*). A complete
/// mirror of what this enumerates is a complete mirror of the account.
abstract interface class AccountSummary implements Model {
  /// Every collection the server reported, empty ones included. A key the
  /// server omitted means "this server does not have that collection", which
  /// [operator []] reads as zero.
  Map<ExportableCollection, CollectionSummary> get collections;

  /// The summary for [collection], or an empty one when it was not reported.
  CollectionSummary operator [](ExportableCollection collection);

  /// Rows across every collection.
  int get total;

  const factory({required Map<ExportableCollection, CollectionSummary> collections}) = _AccountSummary;

  factory fromJson(Map json) = _AccountSummary.fromJson;
}

class _CollectionSummary implements CollectionSummary {
  @override
  final int count;
  @override
  final String? latestId;

  const new({required this.count, this.latestId});

  factory fromJson(Map json) {
    return _CollectionSummary(
      count: switch (json['count']) {
        final int count when count >= 0 => count,
        final other => throw ArgumentError.value(other, 'count', 'missing or negative count'),
      },
      latestId: switch (json['latestId']) {
        null => null,
        final String id when id.isNotEmpty => id,
        final other => throw ArgumentError.value(other, 'latestId', 'invalid id'),
      },
    );
  }

  @override
  Map<String, dynamic> toMap() {
    return {
      'count': count,
      'latestId': ?latestId,
    };
  }
}

class _AccountSummary implements AccountSummary {
  static const _empty = _CollectionSummary(count: 0);

  @override
  final Map<ExportableCollection, CollectionSummary> collections;

  const new({required this.collections});

  factory fromJson(Map json) {
    final raw = switch (json['collections']) {
      final Map collections => collections,
      final other => throw ArgumentError.value(other, 'collections', 'missing collections'),
    };
    return _AccountSummary(
      collections: {
        // A key this build doesn't know is a newer server, not a bad payload:
        // the null-aware entry drops it instead of failing the whole parse.
        for (final MapEntry(:key, :value) in raw.entries)
          ?ExportableCollection.tryParse('$key'): CollectionSummary.fromJson(value as Map),
      },
    );
  }

  @override
  CollectionSummary operator [](ExportableCollection collection) => collections[collection] ?? _empty;

  @override
  int get total => collections.values.fold(0, (running, each) => running + each.count);

  @override
  Map<String, dynamic> toMap() {
    return {
      'collections': {
        for (final MapEntry(:key, :value) in collections.entries) key.name: value.toMap(),
      },
    };
  }
}
