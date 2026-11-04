import 'dart:convert';

import 'package:heart/core/handler.dart';
import 'package:heart/globals/config.dart';
import 'package:heart/globals/globals.dart';
import 'package:heart/inputs/inputs.dart';
import 'package:heart/middleware/aws.dart';
import 'package:heart/middleware/database.dart';
import 'package:heart/middleware/events.dart';
import 'package:heart/models/errors.dart';
import 'package:heart/models/pagination.dart';
import 'package:heart/notifications/sealing.dart';
import 'package:heart/notifications/topics.dart';
import 'package:heart_aws/heart_aws.dart';
import 'package:heart_models/heart_models.dart';
import 'package:logging/logging.dart' as logging;
import 'package:relic/relic.dart';

final _logger = logging.Logger('Threads');

MessageTags _tags(Request req) => req.config.messageTags ?? (throw UnimplementedError('messages are not configured'));

Future<Thread> openThread(Request req) async {
  final connectionId = req.rawPathParameters[#connectionId]!;
  final thread = await req.threadService.openThread(userId: req.userId, connectionId: connectionId);
  return thread ?? (throw NotFound(type: 'Connection', id: connectionId));
}

Future<ThreadList> getThreads(Request req) async {
  return ThreadList(await req.threadService.getThreads(userId: req.userId));
}

Future<Model> addThreadItem(Request req) async {
  final threadId = req.rawPathParameters[#threadId]!;
  final input = await ThreadItemIn.fromRequest(req);
  final parties = await req.threadService.getThreadParties(senderId: req.userId, threadId: threadId);
  if (parties == null) {
    throw const Forbidden(code: 'thread_closed', reason: 'This thread takes no new messages from you.');
  }

  final tags = _tags(req);
  final createdAt = DateTime.timestamp();
  final (item, created) = await req.threadService.addThreadItem(
    senderId: req.userId,
    threadId: threadId,
    id: input.id,
    kind: input.kind,
    content: input.content,
    commitment: input.commitment,
    tag: tags.tag(
      commitment: input.commitment,
      senderId: req.userId,
      recipientId: parties.recipientId,
      at: createdAt,
    ),
    tagKey: tags.currentKey,
    at: input.at,
    createdAt: createdAt,
    subjectType: input.subjectType,
    subjectId: input.subjectId,
  );

  if (!created) return item;
  await req.events.publish(
    queueUrl: req.config.eventsQueueUrl,
    message: {
      'type': 'push.requested',
      'userId': parties.recipientId,
      'topic': PushTopic.coachingMessage.key,
      'name': req.user.displayName ?? '',
      'actorId': req.userId,
      'data': {'threadId': threadId},
    },
  );
  return Created(item);
}

Future<Paginated<ThreadItem>> getThreadItems(Request req) async {
  final query = ThreadItemsQuery.fromRequest(req);
  final page = await req.threadService.getThreadItems(
    userId: req.userId,
    threadId: req.rawPathParameters[#threadId]!,
    since: query.since,
    before: query.before,
    subjectType: query.subjectType,
    subjectId: query.subjectId,
    limit: query.limit,
  );
  return Paginated<ThreadItem>.from(page, itemsKey: 'items', cursorOf: (item) => item.cursor!);
}

Future<Model> markThreadRead(Request req) async {
  final input = await ThreadReadIn.fromRequest(req);
  await req.threadService.markThreadRead(
    userId: req.userId,
    threadId: req.rawPathParameters[#threadId]!,
    cursor: input.cursor,
  );
  throw const NoContent();
}

Future<Model> clearThread(Request req) async {
  final threadId = req.rawPathParameters[#threadId]!;
  final other = await req.threadService.clearThread(userId: req.userId, threadId: threadId);
  if (other != null) {
    await req.events.publish(
      queueUrl: req.config.eventsQueueUrl,
      message: {
        'type': 'push.requested',
        'userId': other,
        'topic': PushTopic.threadCleared.key,
        'data': {'threadId': threadId},
      },
    );
  }
  throw const NoContent();
}

Future<CoachNote> saveNote(Request req) async {
  final input = await NoteIn.fromRequest(req, id: req.rawPathParameters[#noteId]!);
  return req.noteService.saveNote(
    coachId: req.userId,
    id: input.id,
    connectionId: input.connectionId,
    content: input.content,
  );
}

Future<Paginated<CoachNote>> getNotes(Request req) async {
  final query = PageQuery.fromRequest(req);
  final page = await req.noteService.getNotes(
    coachId: req.userId,
    connectionId: req.url.queryParameters['connectionId'],
    cursor: query.cursor,
    limit: query.limit,
  );
  return Paginated<CoachNote>.from(page, itemsKey: 'notes', cursorOf: (note) => note.id);
}

Future<Model> deleteNote(Request req) async {
  await req.noteService.deleteNote(coachId: req.userId, id: req.rawPathParameters[#noteId]!);
  throw const NoContent();
}

/// Checks the words here, in memory, and stores them sealed to a key the server
/// doesn't hold. The alert says a report arrived, and nothing of what it says.
Future<Model> fileReport(Request req) async {
  final input = await ReportIn.fromRequest(req);
  final reviewKey = req.config.reportReviewKey ?? (throw UnimplementedError('reports are not configured'));
  final tags = _tags(req);

  final people = {req.userId, input.reportedId};
  final verified =
      input.messages.any((message) => message.senderId == input.reportedId) &&
      input.messages.every(
        (message) =>
            {message.senderId, message.recipientId}.containsAll(people) &&
            tags.confirms(
              words: message.words,
              reporterKey: message.key,
              commitment: message.commitment,
              tag: message.tag,
              tagKey: message.tagKey,
              senderId: message.senderId,
              recipientId: message.recipientId,
              at: message.createdAt,
            ),
      );

  await req.reportService.fileReport(
    reporterId: req.userId,
    reportedId: input.reportedId,
    connectionId: input.connectionId,
    reason: input.reason,
    sealed: await sealTo(
      reviewKey,
      jsonEncode([
        for (final message in input.messages)
          {'senderId': message.senderId, 'at': message.createdAt.toIso8601String(), 'words': message.words},
      ]),
    ),
    verified: verified,
  );

  try {
    final sns = Sns(credentialsProvider: req.awsConfig.credentialsProvider, region: req.awsConfig.region);
    await sns.publish(
      topicArn: req.config.monitoringTopicArn,
      subject: 'A report was filed',
      message: 'A person filed a report (${input.reason}). Verified: $verified.',
    );
  } catch (e, st) {
    // the report is stored, and an alert must never fail the request it is about
    _logger.warning('failed to alert about a report', e, st);
  }
  throw const NoContent();
}
