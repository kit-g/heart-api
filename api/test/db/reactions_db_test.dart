@Tags(['db'])
library;

import 'package:heart/models/errors.dart';
import 'package:heart_models/heart_models.dart';
import 'package:test/test.dart';

import 'db_test_utility.dart';

/// The `ReactionService` queries against a live Postgres: who may react (the
/// comments' rule, checked in the same statement), one reaction per person per
/// thing, the owner told once per person per workout, the page and the counts,
/// and blocks.
void main() {
  final h = _Harness();

  late String owner;

  Future<String> peer({String? name}) async {
    final id = await h.seedProfile();
    if (name != null) await h.exec('UPDATE profiles SET username = @n WHERE id = @id', {'n': name, 'id': id});
    await h.seedConnection(initiator: owner, target: id);
    return id;
  }

  Future<String> one(String sql, String workout) async {
    final rows = await h.exec(sql, {'w': workout});
    return rows.first.toColumnMap()['id'].toString();
  }

  Future<({Reaction reaction, bool created, String? notify})> react(
    String who,
    String target, {
    CommentTarget type = .workout,
    String kind = 'cheer',
    DateTime? at,
  }) {
    return h.db.setReaction(authorId: who, targetType: type, targetId: target, kind: kind, at: at);
  }

  Future<({Page<Reaction> page, ReactionSummary summary})> read(
    String who,
    String target, {
    CommentTarget type = .workout,
    String? cursor,
    int limit = 50,
  }) {
    return h.db.getReactions(readerId: who, targetType: type, targetId: target, cursor: cursor, limit: limit);
  }

  setUpAll(() async {
    await h.setupDatabase();
    owner = await h.seedProfile();
  });

  tearDownAll(h.teardownDatabase);

  test('a first reaction is made, a second changes its word and keeps when it was left', () async {
    final friend = await peer(name: 'Friend');
    final workout = await h.seedWorkout(userId: owner);

    final first = await react(friend, workout);
    expect(first.created, isTrue);
    expect(first.reaction.kind, 'cheer');
    expect(first.reaction.authorName, 'Friend');
    expect(first.reaction.targetType, CommentTarget.workout);

    final second = await react(friend, workout, kind: 'like');
    expect(second.created, isFalse);
    expect(second.reaction.id, first.reaction.id);
    expect(second.reaction.kind, 'like');
    expect(second.reaction.createdAt, first.reaction.createdAt);

    expect((await read(friend, workout)).page.items.map((r) => r.kind), ['like'], reason: 'one per person');
  });

  test('every kind of target takes one, each on its own', () async {
    final friend = await peer();
    final workout = await h.seedWorkout(userId: owner, withExercise: true);
    final exercise = await one('SELECT id FROM workout_exercises WHERE workout_id = @w', workout);
    final set = await one(
      'SELECT es.id FROM exercise_sets es JOIN workout_exercises we ON we.id = es.workout_exercise_id '
      'WHERE we.workout_id = @w',
      workout,
    );
    final image = await h.insertId(
      'INSERT INTO workout_images (workout_id, user_id, key) VALUES (@w, @u, @k) RETURNING id',
      {'w': workout, 'u': owner, 'k': h.uniqueName('img')},
    );

    for (final (type, id) in [
      (CommentTarget.workout, workout),
      (CommentTarget.workoutExercise, exercise),
      (CommentTarget.exerciseSet, set),
      (CommentTarget.workoutImage, image),
    ]) {
      final (:reaction, :created, notify: _) = await react(friend, id, type: type);
      expect((reaction.targetType, reaction.targetId, created), (type, id, true), reason: type.value);
      expect((await read(friend, id, type: type)).page.items, hasLength(1), reason: type.value);
    }
  });

  test('the owner is told once per person per workout, however they react in it', () async {
    final friend = await peer();
    final workout = await h.seedWorkout(userId: owner, withExercise: true);
    final set = await one(
      'SELECT es.id FROM exercise_sets es JOIN workout_exercises we ON we.id = es.workout_exercise_id '
      'WHERE we.workout_id = @w',
      workout,
    );

    expect((await react(friend, set, type: .exerciseSet)).notify, owner);
    expect((await react(friend, workout)).notify, isNull, reason: 'the same workout');
    await h.db.removeReaction(authorId: friend, targetType: .workout, targetId: workout);
    final again = await react(friend, workout);
    expect((again.created, again.notify), (true, null), reason: 'taken off and left again');

    expect((await react(friend, await h.seedWorkout(userId: owner))).notify, owner, reason: 'another workout');
    expect((await react(owner, await h.seedWorkout(userId: owner))).notify, isNull, reason: 'their own');
  });

  test('a stranger is refused, what the reader can\'t see is missing, and so is what isn\'t there', () async {
    final workout = await h.seedWorkout(userId: owner);
    await expectLater(react(await h.seedProfile(), workout), throwsA(isA<Forbidden>()));
    await expectLater(read(await h.seedProfile(), workout), throwsA(isA<Forbidden>()));

    final friend = await peer();
    await h.exec('UPDATE workouts SET hidden_at = now() WHERE id = @w::uuid', {'w': workout});
    await expectLater(react(friend, workout), throwsA(isA<NotFound>()));
    await expectLater(read(friend, workout), throwsA(isA<NotFound>()));

    await expectLater(react(friend, uuidV7(), type: .exerciseSet), throwsA(isA<NotFound>()));
    await expectLater(react(friend, uuidV7()), throwsA(isA<NotFound>()));
  });

  test('a reaction made offline keeps the device\'s time, and never one ahead of now', () async {
    final friend = await peer();
    final workout = await h.seedWorkout(userId: owner);
    final then = DateTime.utc(2026, 11, 1, 9);
    expect((await react(friend, workout, at: then)).reaction.createdAt, then);

    final ahead = await react(await peer(), workout, at: DateTime.timestamp().add(const Duration(days: 3)));
    expect(ahead.reaction.createdAt.isBefore(DateTime.timestamp().add(const Duration(minutes: 1))), isTrue);
  });

  test('the counts say how many of each word, and the reader\'s own, past the page', () async {
    final (a, b, c) = (await peer(), await peer(), await peer());
    final workout = await h.seedWorkout(userId: owner);
    await react(a, workout);
    await react(b, workout);
    await react(c, workout, kind: 'like');

    final seen = await read(a, workout, limit: 1);
    expect(seen.page.items, hasLength(1));
    expect(seen.summary.counts, {'cheer': 2, 'like': 1});
    expect(seen.summary.mine, 'cheer');
    expect((await read(owner, workout)).summary.mine, isNull);

    final empty = await read(a, await h.seedWorkout(userId: owner));
    expect(empty.summary.counts, isEmpty);
    expect(empty.page.items, isEmpty);
  });

  test('pages newest first by when they reacted, and taking one off is idempotent and one\'s own', () async {
    final workout = await h.seedWorkout(userId: owner);
    final people = [for (var i = 0; i < 3; i++) await peer()];
    for (final (i, person) in people.indexed) {
      await react(person, workout, at: DateTime.utc(2026, 11, 1 + i));
    }

    final first = await read(owner, workout, limit: 2);
    expect(first.page.items.map((r) => r.authorId), [people[2], people[1]]);
    expect(first.page.hasMore, isTrue);
    final second = await read(owner, workout, limit: 2, cursor: first.page.items.last.id);
    expect(second.page.items.map((r) => r.authorId), [people[0]]);
    expect(second.page.hasMore, isFalse);

    await h.db.removeReaction(authorId: people[0], targetType: .workout, targetId: workout);
    await h.db.removeReaction(authorId: people[0], targetType: .workout, targetId: workout);
    expect((await read(owner, workout)).page.items.map((r) => r.authorId), [people[2], people[1]]);
  });

  test('nobody a block stands between the reader and is listed or counted', () async {
    final (reader, blocker) = (await peer(), await peer());
    final workout = await h.seedWorkout(userId: owner);
    await react(blocker, workout);
    await react(reader, workout, kind: 'like');
    await h.exec('INSERT INTO blocks (blocker_id, blocked_id) VALUES (@a, @b)', {'a': blocker, 'b': reader});

    final seen = await read(reader, workout);
    expect(seen.page.items.map((r) => r.authorId), [reader]);
    expect(seen.summary.counts, {'like': 1});
    expect((await read(owner, workout)).summary.counts, {'cheer': 1, 'like': 1});
  });

  test('several of one person\'s requests at once leave one reaction, and every one answers', () async {
    final friend = await peer();
    final workout = await h.seedWorkout(userId: owner);
    final results = await Future.wait([
      for (final kind in ['cheer', 'like', 'cheer', 'like', 'cheer', 'like']) react(friend, workout, kind: kind),
    ]);
    expect(results.where((r) => r.created), hasLength(1));
    expect(results.where((r) => r.notify != null), hasLength(1));
    expect((await read(friend, workout)).page.items, hasLength(1));
  });
}

class _Harness extends DatabaseTestBase;
