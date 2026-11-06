@Tags(['db'])
library;

import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:heart/models/changes.dart';
import 'package:heart/models/errors.dart';
import 'package:heart/notifications/sealing.dart';
import 'package:heart_models/heart_models.dart';
import 'package:postgres/postgres.dart' show Sql;
import 'package:test/test.dart';

import 'db_test_utility.dart';

void main() {
  final h = _Harness();

  setUpAll(h.setupDatabase);
  tearDownAll(h.teardownDatabase);

  Future<(String, String, String)> open() async {
    final (a, b) = (await h.seedProfile(), await h.seedProfile());
    await h.seedConnection(initiator: a, target: b);
    final connection = (await h.db.getConnections(a)).single.connectionId!;
    final thread = (await h.db.openThread(userId: a, connectionId: connection))!;
    return (a, b, thread.id);
  }

  Future<ThreadItem> say(
    String sender,
    String thread, {
    String content = 'sealed',
    String? id,
    DateTime? at,
    String? subjectType,
    String? subjectId,
  }) async {
    final now = DateTime.timestamp();
    final (item, _) = await h.db.addThreadItem(
      senderId: sender,
      threadId: thread,
      id: id ?? uuidV7(),
      kind: 'message',
      content: content,
      commitment: 'c',
      tag: 't',
      tagKey: 'k',
      at: at ?? now,
      createdAt: now,
      subjectType: subjectType,
      subjectId: subjectId,
    );
    return item;
  }

  // Forward reads stop short of any transaction still running, and the other
  // suites sharing this database keep some running: wait for the horizon to pass.
  Future<Page<ThreadItem>> settled(String reader, String thread, String? since, int count) async {
    for (var i = 0; ; i++) {
      final page = await h.db.getThreadItems(userId: reader, threadId: thread, since: since);
      if (page.items.length >= count || i == 50) return page;
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
  }

  Future<List<ThreadItem>> newest(String reader, String thread, {int count = 1}) async {
    return (await settled(reader, thread, null, count)).items;
  }

  // A read hands out cursors, and a send doesn't.
  Future<String> cursorOf(String reader, String thread, ThreadItem item) async {
    for (var i = 0; ; i++) {
      final page = await h.db.getThreadItems(userId: reader, threadId: thread, limit: 100);
      if (page.items.where((each) => each.id == item.id).firstOrNull case final read?) return read.cursor!;
      if (i == 50) fail('${item.id} never became readable');
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
  }

  group('opening', () {
    test('one thread per connection, from either side', () async {
      final (a, b, thread) = await open();
      final connection = (await h.db.getConnections(a)).single.connectionId!;
      expect((await h.db.openThread(userId: b, connectionId: connection))?.id, thread);
    });

    test('not for someone outside it, or a request nobody answered', () async {
      final (a, _, _) = await open();
      final stranger = await h.seedProfile();
      final connection = (await h.db.getConnections(a)).single.connectionId!;
      expect(await h.db.openThread(userId: stranger, connectionId: connection), isNull);

      final (c, d) = (await h.seedProfile(), await h.seedProfile());
      await h.seedConnection(initiator: c, target: d, status: 'pending');
      final pending = (await h.db.getConnections(c)).single.connectionId!;
      expect(await h.db.openThread(userId: c, connectionId: pending), isNull);
    });

    test('not by someone the other person blocked, while the blocker still can', () async {
      final (a, b) = (await h.seedProfile(), await h.seedProfile());
      await h.seedConnection(initiator: a, target: b);
      final connection = (await h.db.getConnections(a)).single.connectionId!;
      await h.exec('INSERT INTO blocks (blocker_id, blocked_id) VALUES (@a, @b)', {'a': a, 'b': b});

      expect(await h.db.openThread(userId: b, connectionId: connection), isNull);
      expect(await h.db.getThreads(userId: a), isEmpty, reason: 'nothing of theirs lands in the inbox');
      expect(await h.db.openThread(userId: a, connectionId: connection), isNotNull);
    });

    test('an open thread answers as the inbox shows it', () async {
      final (a, b, thread) = await open();
      await say(a, thread);
      await say(a, thread);
      final connection = (await h.db.getConnections(b)).single.connectionId!;

      final opened = (await h.db.openThread(userId: b, connectionId: connection))!;
      expect(opened.toMap(), (await h.db.getThreads(userId: b)).single.toMap());
      expect(opened.unread, 2);
      expect(opened.otherName, 'u_$a');
    });
  });

  group('sending', () {
    test('a retry stores it once', () async {
      final (a, b, thread) = await open();
      final id = uuidV7();
      await say(a, thread, id: id);
      await say(a, thread, id: id, content: 'again');

      final items = await newest(b, thread);
      expect(items.single.content, 'sealed');
    });

    test('a retry that overlaps the request it repeats gets the stored message', () async {
      final (a, _, thread) = await open();
      final id = uuidV7();
      final now = DateTime.timestamp();
      final [(item, created)] = await h.runBlocked(
        hold: (tx) async {
          await tx.execute(
            Sql.named('''
              INSERT INTO thread_items (id, thread_id, sender_id, content, commitment, tag, tag_key, at, created_at)
              VALUES (@id::uuid, @thread::uuid, @a, 'sealed', 'c', 't', 'k', now(), now())
            '''),
            parameters: {'id': id, 'thread': thread, 'a': a},
          );
        },
        calls: [
          () => h.db.addThreadItem(
            senderId: a,
            threadId: thread,
            id: id,
            kind: 'message',
            content: 'sealed',
            commitment: 'c',
            tag: 't',
            tagKey: 'k',
            at: now,
            createdAt: now,
          ),
        ],
      );
      expect(item.id, id);
      expect(created, isFalse);
    });

    test('a block landing mid-send says the thread is closed, not that the id is taken', () async {
      final (a, b, thread) = await open();
      await h.exec('INSERT INTO blocks (blocker_id, blocked_id) VALUES (@b, @a)', {'a': a, 'b': b});
      await expectLater(
        say(a, thread),
        throwsA(isA<Forbidden>().having((e) => e.code, 'code', 'thread_closed')),
      );
    });

    test('an id that is someone else\'s is taken', () async {
      final (a, _, thread) = await open();
      final (c, _, other) = await open();
      final id = uuidV7();
      await say(a, thread, id: id);
      await expectLater(
        say(c, other, id: id),
        throwsA(isA<Forbidden>().having((e) => e.code, 'code', 'id_taken')),
      );
    });

    test('a sender stops at 60 a minute, and a retry still answers', () async {
      final (a, _, thread) = await open();
      final first = await say(a, thread);
      await h.exec(
        '''
        INSERT INTO thread_items (id, thread_id, sender_id, content, commitment, tag, tag_key, at, created_at)
        SELECT uuidv7(), @thread::uuid, @a, 'sealed', 'c', 't', 'k', now(), now()
        FROM generate_series(1, 59)
        ''',
        {'thread': thread, 'a': a},
      );
      await expectLater(say(a, thread), throwsA(isA<TooManyRequests>()));
      expect((await say(a, thread, id: first.id)).id, first.id);
    });

    test('a send hands out no cursor, since its place may be past one still writing', () async {
      final (a, _, thread) = await open();
      expect((await say(a, thread)).cursor, isNull);
    });

    test('a pause pauses the sharing, not the conversation', () async {
      final (a, b, thread) = await open();
      await h.exec(
        "UPDATE connections SET status = 'paused' WHERE id = (SELECT connection_id FROM threads WHERE id = @t::uuid)",
        {'t': thread},
      );
      expect((await h.db.getThreadParties(senderId: b, threadId: thread))?.recipientId, a);
      expect((await say(b, thread)).threadId, thread);
    });

    test('takes nothing once the connection ended, or across a block', () async {
      final (a, b, thread) = await open();
      final parties = await h.db.getThreadParties(senderId: a, threadId: thread);
      expect(parties?.recipientId, b);
      expect(parties?.connectionId, (await h.db.getConnections(a)).single.connectionId);
      expect(await h.db.getThreadParties(senderId: await h.seedProfile(), threadId: thread), isNull);

      await h.db.deleteConnection(actorId: a, targetId: b, role: .peer, domain: .fitness);
      expect(await h.db.getThreadParties(senderId: a, threadId: thread), isNull);
      await expectLater(say(a, thread), throwsA(isA<Forbidden>()));
      expect(
        await h.db.getThreadItems(userId: b, threadId: thread).then((page) => page.items),
        isEmpty,
        reason: 'an ended thread stays readable',
      );
    });
  });

  group('reading', () {
    test('a message written offline and stored later is still after the reader', () async {
      final (a, b, thread) = await open();
      final first = await say(a, thread, content: 'first');

      // written days ago with an old id, and only now reaching the server
      final offline = await say(
        a,
        thread,
        content: 'offline',
        id: '01800000-0000-7000-8000-000000000001',
        at: DateTime.utc(2020),
      );

      final since = await settled(b, thread, await cursorOf(b, thread, first), 1);
      expect(since.items.single.id, offline.id);
      expect(since.items.single.at, DateTime.utc(2020), reason: 'the app shows the device time');
    });

    // Text sorts '1000000' before '999999', so a sort on a cast of the transaction id
    // would page past items for good.
    test('order goes by the transaction id as a number, across a digit boundary', () async {
      final (a, b, thread) = await open();
      final (one, two) = (await say(a, thread, content: 'older'), await say(a, thread, content: 'newer'));
      await h.exec("UPDATE thread_items SET xid = '999'::xid8 WHERE id = @id::uuid", {'id': one.id});
      await h.exec("UPDATE thread_items SET xid = '1000'::xid8 WHERE id = @id::uuid", {'id': two.id});

      final items = (await h.db.getThreadItems(userId: b, threadId: thread)).items;
      expect(items.map((item) => item.content), ['newer', 'older']);

      final older = await h.exec('SELECT xid::text, id FROM thread_items WHERE id = @id::uuid', {'id': one.id});
      final forward = await h.db.getThreadItems(
        userId: b,
        threadId: thread,
        since: ChangeCursor(xid: older.first[0]! as String, id: one.id).toString(),
      );
      expect(forward.items.single.content, 'newer');
    });

    test('newest first by default, and back from a point', () async {
      final (a, b, thread) = await open();
      final said = [for (var i = 0; i < 5; i++) await say(a, thread, content: 'm$i')];
      await newest(b, thread, count: 5);

      final first = await h.db.getThreadItems(userId: b, threadId: thread, limit: 2);
      expect(first.items.map((item) => item.content), ['m4', 'm3']);
      expect(first.hasMore, isTrue);

      final next = await h.db.getThreadItems(userId: b, threadId: thread, before: first.items.last.cursor, limit: 2);
      expect(next.items.map((item) => item.content), ['m2', 'm1']);

      final forward = await settled(b, thread, await cursorOf(b, thread, said[2]), 2);
      expect(forward.items.map((item) => item.content), ['m3', 'm4']);
    });

    test('what was said about one thing, down to a set', () async {
      final (a, b, thread) = await open();
      await say(a, thread, content: 'general');
      await say(a, thread, content: 'about the set', subjectType: 'exercise_set', subjectId: 's1');
      await say(a, thread, content: 'about another', subjectType: 'exercise_set', subjectId: 's2');
      await newest(b, thread, count: 3);

      final about = await h.db.getThreadItems(
        userId: b,
        threadId: thread,
        subjectType: 'exercise_set',
        subjectId: 's1',
      );
      expect(about.items.single.content, 'about the set');
    });

    test('a stranger cannot, and someone blocked by the other cannot, while the blocker can', () async {
      final (a, b, thread) = await open();
      await say(a, thread);
      await newest(b, thread);
      final stranger = await h.seedProfile();
      await expectLater(h.db.getThreadItems(userId: stranger, threadId: thread), throwsA(isA<Forbidden>()));

      await h.exec('INSERT INTO blocks (blocker_id, blocked_id) VALUES (@b, @a)', {'a': a, 'b': b});
      await expectLater(h.db.getThreadItems(userId: a, threadId: thread), throwsA(isA<Forbidden>()));
      expect((await h.db.getThreadItems(userId: b, threadId: thread)).items, hasLength(1));
      expect(await h.db.getThreads(userId: a), isEmpty);
      expect(await h.db.getThreads(userId: b), hasLength(1));
    });
  });

  test('the inbox goes by what arrived last, whatever time a device claims', () async {
    final (a, b) = (await h.seedProfile(), await h.seedProfile());
    final c = await h.seedProfile();
    await h.seedConnection(initiator: a, target: b);
    await h.seedConnection(initiator: c, target: b);
    final threads = <String, String>{};
    for (final connection in await h.db.getConnections(b)) {
      final thread = (await h.db.openThread(userId: b, connectionId: connection.connectionId!))!;
      threads[thread.otherId!] = thread.id;
    }

    await say(a, threads[a]!, at: DateTime.utc(9999));
    await say(c, threads[c]!, at: DateTime.utc(2020));

    final inbox = await h.db.getThreads(userId: b);
    expect(inbox.map((thread) => thread.otherId), [c, a]);
    expect(inbox.first.lastAt!.isAfter(inbox.last.lastAt!), isTrue);
  });

  group('unread', () {
    test('counts what the other person said, after the read position, which never moves back', () async {
      final (a, b, thread) = await open();
      final one = await say(a, thread);
      final two = await say(a, thread);
      await say(b, thread);

      expect((await h.db.getThreads(userId: b)).single.unread, 2);
      expect((await h.db.getThreads(userId: a)).single.unread, 1);

      await h.db.markThreadRead(userId: b, threadId: thread, cursor: await cursorOf(b, thread, two));
      expect((await h.db.getThreads(userId: b)).single.unread, 0);

      await h.db.markThreadRead(userId: b, threadId: thread, cursor: await cursorOf(b, thread, one));
      expect((await h.db.getThreads(userId: b)).single.unread, 0);

      await say(a, thread);
      expect((await h.db.getThreads(userId: b)).single.unread, 1);
    });

    test('an offline message stored later still counts', () async {
      final (a, b, thread) = await open();
      final read = await say(a, thread);
      await h.db.markThreadRead(userId: b, threadId: thread, cursor: await cursorOf(b, thread, read));

      await say(a, thread, id: '01800000-0000-7000-8000-000000000002', at: DateTime.utc(2020));
      expect((await h.db.getThreads(userId: b)).single.unread, 1);
    });

    test('a position past anything stored is refused, and moves nothing', () async {
      final (a, b, thread) = await open();
      await say(a, thread);
      final past = ChangeCursor(xid: '18446744073709551615', id: uuidV7()).toString();

      await expectLater(
        h.db.markThreadRead(userId: b, threadId: thread, cursor: past),
        throwsA(isA<BadRequest>().having((e) => e.code, 'code', 'stale_cursor')),
      );
      expect((await h.db.getThreads(userId: b)).single.unread, 1);
      await expectLater(
        h.db.getThreadItems(userId: b, threadId: thread, since: past),
        throwsA(isA<BadRequest>().having((e) => e.code, 'code', 'stale_cursor')),
      );
    });
  });

  group('deleting', () {
    test('either person deletes it for both, and says so on the thread', () async {
      final (a, b, thread) = await open();
      await say(a, thread);

      expect(await h.db.clearThread(userId: b, threadId: thread), a);

      expect((await h.db.getThreadItems(userId: a, threadId: thread)).items, isEmpty);
      final seen = (await h.db.getThreads(userId: a)).single;
      expect(seen.clearedBy, b);
      expect(seen.clearedAt, isNotNull);
      expect(seen.unread, 0);

      await say(a, thread, content: 'still live');
      expect((await newest(b, thread)).single.content, 'still live');
    });

    test('a stranger cannot, and either can after the connection ended', () async {
      final (a, b, thread) = await open();
      await say(a, thread);
      expect(await h.db.clearThread(userId: await h.seedProfile(), threadId: thread), isNull);
      expect(await newest(a, thread), hasLength(1));

      await h.db.deleteConnection(actorId: a, targetId: b, role: .peer, domain: .fitness);
      expect(await h.db.clearThread(userId: b, threadId: thread), a);
    });

    test('an account going leaves the conversation with the other person', () async {
      final (a, b, thread) = await open();
      final item = await say(a, thread);
      await say(b, thread);

      await h.exec('DELETE FROM profiles WHERE id = @a', {'a': a});

      final items = await newest(b, thread, count: 2);
      expect(items, hasLength(2));
      expect(items.firstWhere((each) => each.id == item.id).senderId, isNull);
      final seen = (await h.db.getThreads(userId: b)).single;
      expect(seen.otherId, isNull);
      expect(seen.connectionId, isNull);
    });
  });

  group('notes', () {
    Future<(String, String, String)> coaching() async {
      final (coach, student) = (await h.seedProfile(), await h.seedProfile());
      await h.exec(
        '''
        INSERT INTO connections (initiator_id, target_id, initiator_role, target_role, domain, status)
        VALUES (@c, @s, 'COACH', 'STUDENT', 'fitness', 'active')
        ''',
        {'c': coach, 's': student},
      );
      return (coach, student, (await h.db.getConnections(coach)).single.connectionId!);
    }

    test('a coach writes, edits and reads their own, on one client or all', () async {
      final (coach, _, connection) = await coaching();
      final id = uuidV7();
      await h.db.saveNote(coachId: coach, id: id, connectionId: connection, content: 'one');
      final edited = await h.db.saveNote(coachId: coach, id: id, connectionId: connection, content: 'two');
      expect(edited.content, 'two');

      expect((await h.db.getNotes(coachId: coach, connectionId: connection)).items.single.content, 'two');
      expect((await h.db.getNotes(coachId: coach)).items, hasLength(1));
    });

    test('the student cannot write one, read one, or know', () async {
      final (coach, student, connection) = await coaching();
      await h.db.saveNote(coachId: coach, id: uuidV7(), connectionId: connection, content: 'one');

      await expectLater(
        h.db.saveNote(coachId: student, id: uuidV7(), connectionId: connection, content: 'x'),
        throwsA(isA<NotFound>()),
      );
      expect((await h.db.getNotes(coachId: student, connectionId: connection)).items, isEmpty);
    });

    test('another coach cannot edit through the same id', () async {
      final (coach, _, connection) = await coaching();
      final (other, _, theirs) = await coaching();
      final id = uuidV7();
      await h.db.saveNote(coachId: coach, id: id, connectionId: connection, content: 'one');
      await expectLater(
        h.db.saveNote(coachId: other, id: id, connectionId: theirs, content: 'x'),
        throwsA(isA<Forbidden>().having((e) => e.code, 'code', 'id_taken')),
      );
      expect((await h.db.getNotes(coachId: coach)).items.single.content, 'one');
    });

    test('one about a client who deleted their account still changes', () async {
      final (coach, student, connection) = await coaching();
      final id = uuidV7();
      await h.db.saveNote(coachId: coach, id: id, connectionId: connection, content: 'one');
      await h.exec('DELETE FROM profiles WHERE id = @s', {'s': student});

      final edited = await h.db.saveNote(coachId: coach, id: id, connectionId: connection, content: 'two');
      expect(edited.content, 'two');
      expect(edited.connectionId, isNull);
    });

    test('stay when a client leaves or deletes their account, until the coach deletes them', () async {
      final (coach, student, connection) = await coaching();
      final id = uuidV7();
      await h.db.saveNote(coachId: coach, id: id, connectionId: connection, content: 'one');

      await h.db.deleteConnection(actorId: student, targetId: coach, role: .student, domain: .fitness);
      expect((await h.db.getNotes(coachId: coach)).items, hasLength(1));

      await h.exec('DELETE FROM profiles WHERE id = @s', {'s': student});
      final kept = (await h.db.getNotes(coachId: coach)).items.single;
      expect(kept.connectionId, isNull);

      await h.db.deleteNote(coachId: student, id: id);
      expect((await h.db.getNotes(coachId: coach)).items, hasLength(1));
      await h.db.deleteNote(coachId: coach, id: id);
      expect((await h.db.getNotes(coachId: coach)).items, isEmpty);
    });
  });

  test('a tag made at send still checks against what a read hands back', () async {
    final (a, b, thread) = await open();
    final tags = MessageTags({'k': List.filled(32, 1)});
    final key = base64.encode(List.filled(32, 7));
    final commitment = base64.encode(Hmac(sha256, base64.decode(key)).convert(utf8.encode('words')).bytes);
    final createdAt = DateTime.utc(2026, 11, 4, 12, 30, 15, 123);
    await h.db.addThreadItem(
      senderId: a,
      threadId: thread,
      id: uuidV7(),
      kind: 'message',
      content: 'sealed',
      commitment: commitment,
      tag: tags.tag(commitment: commitment, senderId: a, recipientId: b, at: createdAt),
      tagKey: 'k',
      at: createdAt,
      createdAt: createdAt,
    );

    final read = ThreadItem.fromJson(jsonDecode(jsonEncode((await newest(b, thread)).single.toMap())) as Map);
    final reported = (
      words: 'words',
      key: key,
      commitment: read.commitment,
      tag: read.tag,
      tagKey: read.tagKey,
      senderId: read.senderId!,
      recipientId: b,
      createdAt: DateTime.parse(read.createdAt.toIso8601String()),
    );
    expect(tags.verifies(reporterId: b, reportedId: a, messages: [reported]), isTrue);
  });

  test('a report outlives both people', () async {
    final (a, b) = (await h.seedProfile(), await h.seedProfile());
    await h.db.fileReport(reporterId: a, reportedId: b, reason: 'abuse', sealed: 'sealed', verified: true);
    await h.exec('DELETE FROM profiles WHERE id = ANY(@ids)', {
      'ids': [a, b],
    });
    final kept = await h.exec('SELECT verified, sealed FROM reports WHERE reporter_id = @a', {'a': a});
    expect(kept.single.toColumnMap(), {'verified': true, 'sealed': 'sealed'});
    await h.exec('DELETE FROM reports WHERE reporter_id = @a', {'a': a});
  });
}

class _Harness extends DatabaseTestBase;
