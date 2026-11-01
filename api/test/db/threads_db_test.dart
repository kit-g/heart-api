@Tags(['db'])
library;

import 'package:heart/models/errors.dart';
import 'package:heart_models/heart_models.dart';
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
  });

  group('sending', () {
    test('a retry stores it once', () async {
      final (a, b, thread) = await open();
      final id = uuidV7();
      await say(a, thread, id: id);
      await say(a, thread, id: id, content: 'again');

      final items = (await h.db.getThreadItems(userId: b, threadId: thread)).items;
      expect(items.single.content, 'sealed');
    });

    test('takes nothing once the connection ended, or across a block', () async {
      final (a, b, thread) = await open();
      expect((await h.db.getThreadParties(senderId: a, threadId: thread))?.recipientId, b);
      expect(await h.db.getThreadParties(senderId: await h.seedProfile(), threadId: thread), isNull);

      await h.db.deleteConnection(actorId: a, targetId: b, role: .peer, domain: .fitness);
      expect(await h.db.getThreadParties(senderId: a, threadId: thread), isNull);
      await expectLater(say(a, thread), throwsA(isA<Forbidden>()));
      expect(
        (await h.db.getThreadItems(userId: b, threadId: thread)).items,
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

      final since = await settled(b, thread, first.cursor, 1);
      expect(since.items.single.id, offline.id);
      expect(since.items.single.at, DateTime.utc(2020), reason: 'the app shows the device time');
    });

    test('newest first by default, and back from a point', () async {
      final (a, b, thread) = await open();
      final said = [for (var i = 0; i < 5; i++) await say(a, thread, content: 'm$i')];

      final first = await h.db.getThreadItems(userId: b, threadId: thread, limit: 2);
      expect(first.items.map((item) => item.content), ['m4', 'm3']);
      expect(first.hasMore, isTrue);

      final next = await h.db.getThreadItems(userId: b, threadId: thread, before: first.items.last.cursor, limit: 2);
      expect(next.items.map((item) => item.content), ['m2', 'm1']);

      final forward = await settled(b, thread, said[2].cursor, 2);
      expect(forward.items.map((item) => item.content), ['m3', 'm4']);
    });

    test('what was said about one thing, down to a set', () async {
      final (a, b, thread) = await open();
      await say(a, thread, content: 'general');
      await say(a, thread, content: 'about the set', subjectType: 'exercise_set', subjectId: 's1');
      await say(a, thread, content: 'about another', subjectType: 'exercise_set', subjectId: 's2');

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
      final stranger = await h.seedProfile();
      await expectLater(h.db.getThreadItems(userId: stranger, threadId: thread), throwsA(isA<Forbidden>()));

      await h.exec('INSERT INTO blocks (blocker_id, blocked_id) VALUES (@b, @a)', {'a': a, 'b': b});
      await expectLater(h.db.getThreadItems(userId: a, threadId: thread), throwsA(isA<Forbidden>()));
      expect((await h.db.getThreadItems(userId: b, threadId: thread)).items, hasLength(1));
      expect(await h.db.getThreads(userId: a), isEmpty);
      expect(await h.db.getThreads(userId: b), hasLength(1));
    });
  });

  group('unread', () {
    test('counts what the other person said, after the read position, which never moves back', () async {
      final (a, b, thread) = await open();
      final one = await say(a, thread);
      final two = await say(a, thread);
      await say(b, thread);

      expect((await h.db.getThreads(userId: b)).single.unread, 2);
      expect((await h.db.getThreads(userId: a)).single.unread, 1);

      await h.db.markThreadRead(userId: b, threadId: thread, cursor: two.cursor!);
      expect((await h.db.getThreads(userId: b)).single.unread, 0);

      await h.db.markThreadRead(userId: b, threadId: thread, cursor: one.cursor!);
      expect((await h.db.getThreads(userId: b)).single.unread, 0);

      await say(a, thread);
      expect((await h.db.getThreads(userId: b)).single.unread, 1);
    });

    test('an offline message stored later still counts', () async {
      final (a, b, thread) = await open();
      final read = await say(a, thread);
      await h.db.markThreadRead(userId: b, threadId: thread, cursor: read.cursor!);

      await say(a, thread, id: '01800000-0000-7000-8000-000000000002', at: DateTime.utc(2020));
      expect((await h.db.getThreads(userId: b)).single.unread, 1);
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
      expect((await h.db.getThreadItems(userId: b, threadId: thread)).items.single.content, 'still live');
    });

    test('a stranger cannot, and either can after the connection ended', () async {
      final (a, b, thread) = await open();
      await say(a, thread);
      expect(await h.db.clearThread(userId: await h.seedProfile(), threadId: thread), isNull);
      expect((await h.db.getThreadItems(userId: a, threadId: thread)).items, hasLength(1));

      await h.db.deleteConnection(actorId: a, targetId: b, role: .peer, domain: .fitness);
      expect(await h.db.clearThread(userId: b, threadId: thread), a);
    });

    test('an account going leaves the conversation with the other person', () async {
      final (a, b, thread) = await open();
      final item = await say(a, thread);
      await say(b, thread);

      await h.exec('DELETE FROM profiles WHERE id = @a', {'a': a});

      final items = (await h.db.getThreadItems(userId: b, threadId: thread)).items;
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
        throwsA(isA<NotFound>()),
      );
      expect((await h.db.getNotes(coachId: coach)).items.single.content, 'one');
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
