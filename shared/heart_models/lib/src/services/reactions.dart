import '../models/pagination.dart';
import '../models/reaction.dart';

/// Reactions on what people can read. Who may react to a thing, and read its
/// reactions, is who may comment on it: each call checks that itself, with the
/// comments' rule, and throws for a target the caller can't read.
abstract interface class ReactionService {
  /// Leaves [kind] on the target as [authorId]'s one reaction to it, replacing a
  /// word they left before. [at] is when they did it, by their device; never
  /// later than now. `created` is false when they had one already. `notify` names
  /// the owner to tell, and is null unless this is [authorId]'s first reaction
  /// to anything in that workout, and the workout isn't their own.
  Future<({Reaction reaction, bool created, String? notify})> setReaction({
    required String authorId,
    required ReactionTarget targetType,
    required String targetId,
    required String kind,
    DateTime? at,
  });

  /// Takes [authorId]'s reaction off the target. Nothing there is not an error,
  /// and no read is needed: someone who lost sight of a workout can still take
  /// theirs off.
  Future<void> removeReaction({
    required String authorId,
    required ReactionTarget targetType,
    required String targetId,
  });

  /// Who reacted to the target, newest first, and how many of each word there are,
  /// with [readerId]'s own. Neither counts anyone a block stands between the reader
  /// and.
  Future<({Page<Reaction> page, ReactionSummary summary})> getReactions({
    required String readerId,
    required ReactionTarget targetType,
    required String targetId,
    String? cursor,
    int limit = 50,
  });
}
