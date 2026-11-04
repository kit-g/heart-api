import 'package:heart_models/heart_models.dart';

/// Where a page of the coach's feed starts: after the item at [at] with [id].
typedef FeedCursor = ({DateTime at, String id});

/// A summary that needs working out again, with what that takes.
typedef DirtySummary = ({String connectionId, String coachId, String studentId, int generation, Program? program});

/// A coach's view across their clients. API-side, like [ProgramService].
abstract interface class RosterService {
  /// This coach's summaries marked as changed, all of them.
  Future<List<DirtySummary>> getDirtySummaries({required String coachId});

  /// Works out one summary again from what the coach can read, given where the
  /// program stands, which is a fold done in Dart. It stays dirty if something moved
  /// [generation] on since it was read.
  Future<void> refreshSummary({
    required String connectionId,
    required String coachId,
    required String studentId,
    required int generation,
    String? programId,
    String? programName,
    int? programWeek,
    int? programWeeks,
    required bool ending,
  });

  /// A page of clients, those who need a word first. [reason] keeps those it applies
  /// to. [former] lists former clients, with no more than who and when.
  Future<Page<ClientSummary>> getRoster({
    required String coachId,
    String? reason,
    bool former = false,
    OrderedCursor? cursor,
    int limit = 50,
  });

  /// The coach has looked: reasons from now on count only what comes after. False
  /// when [connectionId] isn't one of this coach's clients.
  Future<bool> markReviewed({required String coachId, required String connectionId, DateTime? at});

  /// Finished workouts, skips and programs ending across their clients, newest first.
  Future<Page<CoachFeedItem>> getCoachFeed({required String coachId, FeedCursor? cursor, int limit = 50});
}
