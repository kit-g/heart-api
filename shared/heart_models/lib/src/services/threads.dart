import '../models/pagination.dart';
import '../models/thread.dart';

/// A connection's two people, as a send needs them, and the connection, so the
/// recipient's settings for that one person apply.
typedef ThreadParties = ({String threadId, String senderId, String recipientId, String connectionId});

abstract interface class ThreadService {
  /// Gets or opens the thread of a connection [userId] is in. Null if they aren't,
  /// or it was never accepted.
  Future<Thread?> openThread({required String userId, required String connectionId});

  /// The two people of a live thread, as [senderId] would write in it. Null when
  /// they can't: it isn't theirs, its connection has ended, or a block stands.
  Future<ThreadParties?> getThreadParties({required String senderId, required String threadId});

  /// Stores an item once. `false` if this id had already arrived.
  Future<(ThreadItem, bool created)> addThreadItem({
    required String senderId,
    required String threadId,
    required String id,
    required String kind,
    required String content,
    required String commitment,
    required String tag,
    required String tagKey,
    required DateTime at,
    required DateTime createdAt,
    String? subjectType,
    String? subjectId,
  });

  /// This person's inbox, most recent first. Threads where the other person blocked
  /// them don't appear.
  Future<List<Thread>> getThreads({required String userId});

  /// Items after [since], in stored order, or before [before], newest first, or the
  /// newest when neither is given. Throws unless the thread is [userId]'s to read.
  Future<Page<ThreadItem>> getThreadItems({
    required String userId,
    required String threadId,
    String? since,
    String? before,
    String? subjectType,
    String? subjectId,
    int limit = 50,
  });

  /// Moves [userId]'s read position forward, never back. Throws if [userId] can't
  /// read the thread.
  Future<void> markThreadRead({required String userId, required String threadId, required String cursor});

  /// Deletes everything said, for both sides. Who else to tell is the answer, null
  /// once they have gone. Throws if the thread isn't [userId]'s.
  Future<String?> clearThread({required String userId, required String threadId});
}

abstract interface class CoachNoteService {
  /// Writes a note on a client of [coachId]'s, idempotent on its id.
  Future<CoachNote> saveNote({
    required String coachId,
    required String id,
    required String connectionId,
    required String content,
  });

  /// [coachId]'s notes, on one client or on all of them.
  Future<Page<CoachNote>> getNotes({required String coachId, String? connectionId, String? cursor, int limit = 50});

  Future<void> deleteNote({required String coachId, required String id});
}

abstract interface class ReportService {
  Future<void> fileReport({
    required String reporterId,
    required String reportedId,
    String? connectionId,
    required String reason,
    required String sealed,
    required bool verified,
  });
}
