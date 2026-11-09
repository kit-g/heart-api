part of 'inputs.dart';

/// Postgres refuses NUL in text, and JSON allows it: without this, a request that
/// can never succeed answers 500 and gets retried.
bool _storable(String text) => !text.contains('\u0000');

/// A string and nothing else, so nothing readable can ride in structure.
String _ciphertext(Map<String, dynamic> json) {
  return switch (json['content']) {
    final String content when content.isNotEmpty && content.length <= 16384 && _storable(content) => content,
    _ => throw const BadRequest(reason: 'content must be text of at most 16 KB'),
  };
}

/// The ids in the thread, note and connection paths, checked before anything casts them: one
/// that can't be an id answers like one that isn't there.
extension ThreadPaths on Request {
  String get threadId => _uuidPath(#threadId, 'Thread');

  String get connectionIdInPath => _uuidPath(#connectionId, 'Connection');

  String get noteId => _uuidPath(#noteId, 'Note');

  String _uuidPath(Symbol name, String type) {
    return switch (rawPathParameters[name]!) {
      final id when isUuidV7(id) => id,
      final id => throw NotFound(type: type, id: id),
    };
  }
}

/// `POST /threads/:threadId/items`.
class ThreadItemIn {
  final String id;
  final String kind;
  final String content;
  final String commitment;
  final DateTime at;
  final String? subjectType;
  final String? subjectId;

  const new _({
    required this.id,
    required this.kind,
    required this.content,
    required this.commitment,
    required this.at,
    this.subjectType,
    this.subjectId,
  });

  static Future<ThreadItemIn> fromRequest(Request req) async {
    final json = await req.json();
    final id = json.string('id');
    if (!isUuidV7(id)) throw const BadRequest(reason: 'id must be a UUIDv7');

    final kind = switch (json['kind']) {
      null => 'message',
      final String kind when threadItemKinds.containsKey(kind) => kind,
      _ => throw const BadRequest(code: 'invalid_kind', reason: 'a thread takes messages and reactions to them'),
    };

    final (subjectType, subjectId) = switch ((json['subjectType'], json['subjectId'])) {
      (null, null) => (null, null),
      (final String type, final String id)
          when _snakeWord.hasMatch(type) && id.isNotEmpty && id.length <= 64 && _storable(id) =>
        (
          type,
          id,
        ),
      _ => throw const BadRequest(reason: 'a subject has a subjectType and a subjectId'),
    };
    // a reaction is to one message, named by its id
    if (kind == 'reaction' && (subjectType != 'message' || !isUuidV7(subjectId!))) {
      throw const BadRequest(code: 'invalid_subject', reason: 'a reaction is to a message: subjectType message');
    }

    return ThreadItemIn._(
      id: id,
      kind: kind,
      content: _ciphertext(json),
      commitment: _commitment(json['commitment']),
      at: switch (json['at']) {
        final String at when DateTime.tryParse(at) != null => DateTime.parse(at),
        _ => throw const BadRequest(reason: 'at must be an ISO-8601 time'),
      },
      subjectType: subjectType,
      subjectId: subjectId,
    );
  }
}

/// 32 bytes, base64, and required from the first message, so every one can be reported.
String _commitment(Object? value) {
  try {
    if (value case final String commitment when base64.decode(commitment).length == 32) return commitment;
  } on FormatException {
    // falls through to the refusal
  }
  throw const BadRequest(code: 'invalid_commitment', reason: 'commitment must be 32 bytes, base64');
}

/// `GET /threads/:threadId/items?since=&before=&subjectType=&subjectId=&limit=`.
class ThreadItemsQuery {
  final String? since;
  final String? before;
  final String? subjectType;
  final String? subjectId;
  final int limit;

  const new _({this.since, this.before, this.subjectType, this.subjectId, required this.limit});

  static ThreadItemsQuery fromRequest(Request req) {
    final query = req.url.queryParameters;
    final since = query['since'];
    final before = query['before'];
    if (since != null && before != null) throw const BadRequest(reason: 'since or before, not both');
    final (subjectType, subjectId) = (query['subjectType'], query['subjectId']);
    if (![subjectType, subjectId].nonNulls.every(_storable)) {
      throw const BadRequest(reason: 'a subject has a subjectType and a subjectId');
    }
    return ThreadItemsQuery._(
      since: since,
      before: before,
      subjectType: subjectType,
      subjectId: subjectId,
      limit: PageQuery.fromRequest(req).limit,
    );
  }
}

/// `PUT /threads/:threadId/read` — `{cursor}`.
class ThreadReadIn {
  final String cursor;

  const new _(this.cursor);

  static Future<ThreadReadIn> fromRequest(Request req) async {
    return ThreadReadIn._((await req.json()).string('cursor'));
  }
}

/// `PUT /notes/:noteId` — `{connectionId, content}`.
class NoteIn {
  final String id;
  final String connectionId;
  final String content;

  const new _({required this.id, required this.connectionId, required this.content});

  static Future<NoteIn> fromRequest(Request req, {required String id}) async {
    if (!isUuidV7(id)) throw const BadRequest(reason: 'id must be a UUIDv7');
    final json = await req.json();
    final connectionId = json.string('connectionId');
    if (!isUuidV7(connectionId)) throw const BadRequest(reason: 'connectionId must be a connection\'s id');
    return NoteIn._(id: id, connectionId: connectionId, content: _ciphertext(json));
  }
}

/// `GET /notes?connectionId=&cursor=&limit=`.
class NotesQuery {
  final String? connectionId;
  final String? cursor;
  final int limit;

  const new _({this.connectionId, this.cursor, required this.limit});

  static NotesQuery fromRequest(Request req) {
    final page = PageQuery.fromRequest(req);
    return NotesQuery._(
      connectionId: switch (req.url.queryParameters['connectionId']) {
        null => null,
        final String id when isUuidV7(id) => id,
        _ => throw const BadRequest(reason: 'connectionId must be a connection\'s id'),
      },
      cursor: switch (page.cursor) {
        null => null,
        final String cursor when isUuidV7(cursor) => cursor,
        _ => throw const BadRequest(reason: 'cursor must be the one the previous page returned'),
      },
      limit: page.limit,
    );
  }
}

/// `POST /reports`.
class ReportIn {
  final String reportedId;
  final String? connectionId;
  final String reason;
  final List<ReportedMessage> messages;

  const new _({required this.reportedId, this.connectionId, required this.reason, required this.messages});

  static const _maxMessages = 100;

  /// An account id is at most this long.
  static const _maxId = 128;

  /// What a message's ciphertext can hold, opened.
  static const _maxWords = 16384;

  static Future<ReportIn> fromRequest(Request req) async {
    final json = await req.json();
    final reason = json.string('reason');
    if (!_snakeWord.hasMatch(reason)) throw const BadRequest(reason: 'reason must be a snake_case word');
    final messages = switch (json['messages']) {
      null => const <Object?>[],
      final List messages when messages.length <= _maxMessages => messages,
      _ => throw const BadRequest(reason: 'messages must be a list of at most $_maxMessages'),
    };
    return ReportIn._(
      reportedId: switch (json['reportedId']) {
        final String id when id.isNotEmpty && id.length <= _maxId && _storable(id) => id,
        _ => throw const BadRequest(reason: 'reportedId must be a person\'s id'),
      },
      connectionId: switch (json['connectionId']) {
        null => null,
        final String id when isUuidV7(id) => id,
        _ => throw const BadRequest(reason: 'connectionId must be a connection\'s id'),
      },
      reason: reason,
      messages: [for (final message in messages) _message(message)],
    );
  }

  static ReportedMessage _message(Object? message) {
    return switch (message) {
      {
        'words': final String words,
        'key': final String key,
        'commitment': final String commitment,
        'tag': final String tag,
        'tagKey': final String tagKey,
        'senderId': final String senderId,
        'recipientId': final String recipientId,
        'createdAt': final String createdAt,
      }
          when words.length <= _maxWords && DateTime.tryParse(createdAt) != null =>
        (
          words: words,
          key: key,
          commitment: commitment,
          tag: tag,
          tagKey: tagKey,
          senderId: senderId,
          recipientId: recipientId,
          createdAt: DateTime.parse(createdAt),
        ),
      _ => throw const BadRequest(reason: 'a reported message carries its words and what proves them'),
    };
  }
}
