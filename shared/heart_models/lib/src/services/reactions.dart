import '../models/pagination.dart';
import '../models/reaction.dart';

/// Reactions on what people can read. Who may react to what is the comments'
/// rule ([CommentService.accessOfTarget]); this only stores and reads them.
abstract interface class ReactionService {
  /// Leaves [kind] on the target as [authorId]'s one reaction to it, replacing a
  /// word they left before. `created` is false when they had one already.
  /// Throws if the target doesn't exist.
  Future<(Reaction, bool created)> setReaction({
    required String authorId,
    required ReactionTarget targetType,
    required String targetId,
    required String kind,
  });

  /// Takes [authorId]'s reaction off the target. Nothing there is not an error.
  Future<void> removeReaction({
    required String authorId,
    required ReactionTarget targetType,
    required String targetId,
  });

  /// Who reacted to the target, newest first.
  Future<Page<Reaction>> listReactions({
    required ReactionTarget targetType,
    required String targetId,
    String? cursor,
    int limit = 50,
  });

  /// How many of each word the target has, and [readerId]'s own.
  Future<ReactionSummary> summarizeReactions({
    required String readerId,
    required ReactionTarget targetType,
    required String targetId,
  });
}
