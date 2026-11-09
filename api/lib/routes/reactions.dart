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
/// hears of a person's reactions to a workout once, never of their own.
Future<Model> setReaction(Request req) async {
  final target = req.reactionTarget;
  final input = await ReactionSetIn.fromRequest(req);
  final (:reaction, :created, :notify) = await req.reactionService.setReaction(
    authorId: req.userId,
    targetType: target.type,
    targetId: target.id,
    kind: input.kind,
    at: input.at,
  );
  if (notify != null) {
    await req.events.publish(
      queueUrl: req.config.eventsQueueUrl,
      message: {
        'type': 'push.requested',
        'userId': notify,
        'topic': PushTopic.reactionCreated.key,
        'variant': target.type.value,
        'name': ?req.user.displayName,
        'actorId': req.userId,
        'data': {'targetType': target.type.value, 'targetId': target.id},
      },
    );
  }
  return created ? Created(reaction) : reaction;
}

/// Idempotent: nothing to take off is not an error.
Future<Model> removeReaction(Request req) async {
  final target = req.reactionTarget;
  await req.reactionService.removeReaction(authorId: req.userId, targetType: target.type, targetId: target.id);
  throw const NoContent();
}

/// Who reacted, newest first, with the counts of each word and the caller's own.
Future<Paginated<Reaction>> getReactions(Request req) async {
  final target = req.reactionTarget;
  final ReactionsQuery(:page) = ReactionsQuery.fromRequest(req);
  final (page: reactions, :summary) = await req.reactionService.getReactions(
    readerId: req.userId,
    targetType: target.type,
    targetId: target.id,
    cursor: page.cursor,
    limit: page.limit,
  );
  return Paginated<Reaction>.from(
    reactions,
    itemsKey: 'reactions',
    cursorOf: (reaction) => reaction.id,
    extra: {'counts': summary.counts, 'mine': ?summary.mine},
  );
}
