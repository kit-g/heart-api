@Tags(['db'])
library;

import 'package:heart/models/errors.dart';
import 'package:heart_models/heart_models.dart';
import 'package:test/test.dart';

import 'db_test_utility.dart';

/// The `ReactionService` queries against a live Postgres: one reaction per person
/// per thing, a changed word, the four kinds of target, the page and the counts.
/// Who may react is the comments' rule, tested where comments' access is.
void main() {
  final h = _Harness();

  late String owner;
  late String friend;
  late String other;

  Future<String> one(String sql, String workout) async {
    final rows = await h.exec(sql, {'w': workout});
    return rows.first.toColumnMap()['id'].toString();
  }

  setUpAll(() async {
    await h.setupDatabase();
    owner = await h.seedProfile();
    friend = await h.seedProfile();
    other = await h.seedProfile();
    await h.exec("UPDATE profiles SET username = 'Friend' WHERE id = @id", {'id': friend});
  });

  tearDownAll(h.teardownDatabase);

  test('a first reaction is made, a second changes its word and keeps when it was left', () async {
    final workout = await h.seedWorkout(userId: owner);

    final (first, created) = await h.db.setReaction(
      authorId: friend,
      targetType: .workout,
      targetId: workout,
      kind: 'cheer',
    );
    expect(created, isTrue);
    expect(
      (first.kind, first.authorName, first.targetType, first.targetId),
      ('cheer', 'Friend', CommentTarget.workout, workout),
    );

    final (second, again) = await h.db.setReaction(
      authorId: friend,
      targetType: .workout,
      targetId: workout,
      kind: 'like',
    );
    expect(again, isFalse);
    expect(second.id, first.id);
    expect(second.kind, 'like');
    expect(second.createdAt, first.createdAt);

    final page = await h.db.listReactions(targetType: .workout, targetId: workout);
    expect(page.items.map((r) => r.kind), ['like'], reason: 'one per person per thing');
  });

  test('every kind of target takes one, each on its own', () async {
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
      final (reaction, created) = await h.db.setReaction(
        authorId: friend,
        targetType: type,
        targetId: id,
        kind: 'cheer',
      );
      expect((reaction.targetType, reaction.targetId, created), (type, id, true), reason: type.value);
      expect(
        (await h.db.listReactions(targetType: type, targetId: id)).items,
        hasLength(1),
        reason: type.value,
      );
    }
  });

  test('a target that does not exist is refused', () async {
    await expectLater(
      h.db.setReaction(authorId: friend, targetType: .exerciseSet, targetId: uuidV7(), kind: 'cheer'),
      throwsA(isA<NotFound>()),
    );
  });

  test('the counts say how many of each word, and the reader\'s own', () async {
    final workout = await h.seedWorkout(userId: owner);
    await h.db.setReaction(authorId: friend, targetType: .workout, targetId: workout, kind: 'cheer');
    await h.db.setReaction(authorId: other, targetType: .workout, targetId: workout, kind: 'cheer');
    await h.db.setReaction(authorId: owner, targetType: .workout, targetId: workout, kind: 'like');

    final mine = await h.db.summarizeReactions(readerId: friend, targetType: .workout, targetId: workout);
    expect(mine.counts, {'cheer': 2, 'like': 1});
    expect(mine.mine, 'cheer');

    final none = await h.db.summarizeReactions(
      readerId: await h.seedProfile(),
      targetType: .workout,
      targetId: workout,
    );
    expect(none.mine, isNull);

    final empty = await h.db.summarizeReactions(
      readerId: friend,
      targetType: .workout,
      targetId: await h.seedWorkout(userId: owner),
    );
    expect(empty.counts, isEmpty);
    expect(empty.mine, isNull);
  });

  test('pages newest first, and taking one off is idempotent and only one\'s own', () async {
    final workout = await h.seedWorkout(userId: owner);
    final people = [for (var i = 0; i < 3; i++) await h.seedProfile()];
    for (final person in people) {
      await h.db.setReaction(authorId: person, targetType: .workout, targetId: workout, kind: 'cheer');
    }

    final first = await h.db.listReactions(targetType: .workout, targetId: workout, limit: 2);
    expect(first.items.map((r) => r.authorId), [people[2], people[1]]);
    expect(first.hasMore, isTrue);
    final second = await h.db.listReactions(
      targetType: .workout,
      targetId: workout,
      limit: 2,
      cursor: first.items.last.id,
    );
    expect(second.items.map((r) => r.authorId), [people[0]]);
    expect(second.hasMore, isFalse);

    await h.db.removeReaction(authorId: people[0], targetType: .workout, targetId: workout);
    await h.db.removeReaction(authorId: people[0], targetType: .workout, targetId: workout);
    final left = await h.db.listReactions(targetType: .workout, targetId: workout);
    expect(left.items.map((r) => r.authorId), [people[2], people[1]]);
  });

  test('two of one person\'s requests at once leave one reaction', () async {
    final workout = await h.seedWorkout(userId: owner);
    final results = await Future.wait([
      for (final kind in ['cheer', 'like', 'cheer', 'like'])
        h.db.setReaction(authorId: friend, targetType: .workout, targetId: workout, kind: kind),
    ]);
    expect(results.where((r) => r.$2), hasLength(1), reason: 'one of them made it');
    expect((await h.db.listReactions(targetType: .workout, targetId: workout)).items, hasLength(1));
  });
}

class _Harness extends DatabaseTestBase;
