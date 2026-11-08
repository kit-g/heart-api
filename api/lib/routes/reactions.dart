import 'package:heart/core/handler.dart';
import 'package:heart/globals/config.dart';
import 'package:heart/globals/globals.dart';
import 'package:heart/inputs/inputs.dart';
import 'package:heart/middleware/database.dart';
import 'package:heart/middleware/events.dart';
import 'package:heart/models/errors.dart';
import 'package:heart/models/pagination.dart';
import 'package:heart/notifications/topics.dart';
import 'package:heart_models/heart_models.dart';
import 'package:relic/relic.dart';

/// Leaves the caller's one reaction on the target, or changes its word. The owner
/// hears of a new one, never of a change and never of their own.
Future<Model> setReaction(Request req) async {
  final target = req.reactionTarget;
  final input = await ReactionSetIn.fromRequest(req);
  final ownerId = await _ownerIfReadable(req, target);
  final (reaction, created) = await req.reactionService.setReaction(
    authorId: req.userId,
    targetType: target.type,
    targetId: target.id,
    kind: input.kind,
  );
  if (created && ownerId != req.userId) {
    await req.events.publish(
      queueUrl: req.config.eventsQueueUrl,
      message: {
        'type': 'push.requested',
        'userId': ownerId,
        'topic': PushTopic.reactionCreated.key,
        'variant': target.type.value,
        'actorId': req.userId,
        'data': {'targetType': target.type.value, 'targetId': target.id},
      },
    );
  }
  return created ? Created(reaction) : reaction;
}

/// Idempotent: nothing to take off is not an error. Someone who can no longer
/// read the target can still take their reaction off it.
Future<Model> removeReaction(Request req) async {
  final target = req.reactionTarget;
  await req.reactionService.removeReaction(authorId: req.userId, targetType: target.type, targetId: target.id);
  throw const NoContent();
}

/// Who reacted, newest first, with the counts of each word and the caller's own.
Future<Paginated<Reaction>> getReactions(Request req) async {
  final target = req.reactionTarget;
  final query = ReactionsQuery.fromRequest(req);
  await _ownerIfReadable(req, target);
  final (page, summary) = await (
    req.reactionService.listReactions(
      targetType: target.type,
      targetId: target.id,
      cursor: query.cursor,
      limit: query.limit,
    ),
    req.reactionService.summarizeReactions(readerId: req.userId, targetType: target.type, targetId: target.id),
  ).wait;
  return Paginated<Reaction>.from(
    page,
    itemsKey: 'reactions',
    cursorOf: (reaction) => reaction.id,
    extra: {'counts': summary.counts, 'mine': ?summary.mine},
  );
}

/// Comments' rule, so whoever can comment on a thing can react to it: a stranger is
/// refused, and what the reader can't see doesn't exist for them.
Future<String> _ownerIfReadable(Request req, ({ReactionTarget type, String id}) target) async {
  final access = await req.commentService.accessOfTarget(
    readerId: req.userId,
    targetType: target.type,
    targetId: target.id,
  );
  return switch (access) {
    null => throw NotFound(type: target.type.value, id: target.id),
    (ownerId: _, related: false, readable: _) => throw const Forbidden(
      reason: 'not connected to the owner of this content',
    ),
    (ownerId: _, related: true, readable: false) => throw NotFound(type: target.type.value, id: target.id),
    (:final ownerId, related: true, readable: true) => ownerId,
  };
}
