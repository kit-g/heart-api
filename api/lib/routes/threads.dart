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
import 'package:heart/models/thread_kinds.dart';
import 'package:heart/notifications/sealing.dart';
import 'package:heart/notifications/topics.dart';
import 'package:heart_models/heart_models.dart';
import 'package:relic/relic.dart';

MessageTags _tags(Request req) => req.config.messageTags ?? (throw UnimplementedError('messages are not configured'));

Future<Thread> openThread(Request req) async {
  final connectionId = req.connectionIdInPath;
  final thread = await req.threadService.openThread(userId: req.userId, connectionId: connectionId);
  return thread ?? (throw NotFound(type: 'Connection', id: connectionId));
}

Future<ThreadList> getThreads(Request req) async {
  return ThreadList(await req.threadService.getThreads(userId: req.userId));
}

Future<Model> addThreadItem(Request req) async {
  final threadId = req.threadId;
  final input = await ThreadItemIn.fromRequest(req);
  final parties = await req.threadService.getThreadParties(senderId: req.userId, threadId: threadId);
  if (parties == null) {
    throw const Forbidden(code: 'thread_closed', reason: 'This thread takes no new messages from you.');
  }

  final tags = _tags(req);
  // Milliseconds only: the tag signs this time as text, and a device that keeps a
  // time to the millisecond (a web build, say) has to be able to write it back
  // exactly when it reports the message.
  final createdAt = DateTime.fromMillisecondsSinceEpoch(DateTime.timestamp().millisecondsSinceEpoch, isUtc: true);
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

  // A quiet kind, such as a reaction, is found on the other person's next read. A
  // retry asks again too: it may be retrying because this push failed after the
  // message was stored, and pushes on this topic collapse into one on the device.
  if (threadItemKinds[input.kind]?.pushes != true) return created ? Created(item) : item;
  await req.events.publish(
    queueUrl: req.config.eventsQueueUrl,
    message: {
      'type': 'push.requested',
      'userId': parties.recipientId,
      'topic': PushTopic.coachingMessage.key,
      'name': ?req.user.displayName,
      'actorId': req.userId,
      'connectionId': parties.connectionId,
      'data': {'threadId': threadId},
    },
  );
  return created ? Created(item) : item;
}

Future<Paginated<ThreadItem>> getThreadItems(Request req) async {
  final threadId = req.threadId;
  final query = ThreadItemsQuery.fromRequest(req);
  final page = await req.threadService.getThreadItems(
    userId: req.userId,
    threadId: threadId,
    since: query.since,
    before: query.before,
    subjectType: query.subjectType,
    subjectId: query.subjectId,
    limit: query.limit,
  );
  return Paginated<ThreadItem>.from(page, itemsKey: 'items', cursorOf: (item) => item.cursor!);
}

Future<Model> markThreadRead(Request req) async {
  final threadId = req.threadId;
  final input = await ThreadReadIn.fromRequest(req);
  await req.threadService.markThreadRead(userId: req.userId, threadId: threadId, cursor: input.cursor);
  throw const NoContent();
}

Future<Model> clearThread(Request req) async {
  final threadId = req.threadId;
  final other = await req.threadService.clearThread(userId: req.userId, threadId: threadId);
  if (other != null) {
    await req.events.publish(
      queueUrl: req.config.eventsQueueUrl,
      message: {
        'type': 'push.requested',
        'userId': other,
        'topic': PushTopic.threadCleared.key,
        'actorId': req.userId,
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
  final query = NotesQuery.fromRequest(req);
  final page = await req.noteService.getNotes(
    coachId: req.userId,
    connectionId: query.connectionId,
    cursor: query.cursor,
    limit: query.limit,
  );
  return Paginated<CoachNote>.from(page, itemsKey: 'notes', cursorOf: (note) => note.id);
}

Future<Model> deleteNote(Request req) async {
  await req.noteService.deleteNote(coachId: req.userId, id: req.noteId);
  throw const NoContent();
}

/// Checks the words here, in memory, and stores them sealed to a key the server
/// doesn't hold. The alert says a report arrived, and nothing of what it says.
Future<Model> fileReport(Request req) async {
  final input = await ReportIn.fromRequest(req);
  final reviewKey = req.config.reportReviewKey ?? (throw UnimplementedError('reports are not configured'));
  final verified = _tags(req).verifies(
    reporterId: req.userId,
    reportedId: input.reportedId,
    messages: input.messages,
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

  await req.alertOwner(
    subject: 'A report was filed',
    message: 'A person filed a report (${input.reason}). Verified: $verified.',
  );
  throw const NoContent();
}
