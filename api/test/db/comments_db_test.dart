@Tags(['db'])
library;

import 'package:heart/models/errors.dart';
import 'package:heart_models/heart_models.dart';
import 'package:test/test.dart';

import 'db_test_utility.dart';

/// Full integration coverage of the `CommentService` query strings against a
/// live Postgres: create/list/edit/delete plus `ownerOfTarget`, exercising the
/// polymorphic-target CASE expressions and the author-scoping the SQL encodes.
///
/// Tagged `db` — skipped by the default `dart test`. Run with:
///   dart test --run-skipped -t db
void main() {
  final h = _Harness();

  late String ownerId; // owns the workouts comments attach to
  late String authorId; // writes the comments
  late String otherId; // a different profile, for author-scoping checks

  /// Resolves the single workout_exercise id of [workoutId] (seeded via
  /// `withExercise: true`). No shared helper exposes it, so we read it directly.
  Future<String> workoutExerciseOf(String workoutId) async {
    final rows = await h.exec(
      'SELECT id FROM workout_exercises WHERE workout_id = @w LIMIT 1',
      {'w': workoutId},
    );
    return rows.first.toColumnMap()['id'].toString();
  }

  /// Resolves the single exercise_set id under [workoutId]'s exercise.
  Future<String> exerciseSetOf(String workoutId) async {
    final rows = await h.exec(
      'SELECT es.id FROM exercise_sets es '
      'JOIN workout_exercises we ON we.id = es.workout_exercise_id '
      'WHERE we.workout_id = @w LIMIT 1',
      {'w': workoutId},
    );
    return rows.first.toColumnMap()['id'].toString();
  }

  /// Inserts a gallery image on [workoutId] and returns its id. No shared
  /// helper covers workout_images, so raw SQL is used.
  Future<String> seedImage(String workoutId, String userId) {
    return h.insertId(
      'INSERT INTO workout_images (workout_id, user_id, key) VALUES (@w, @u, @k) RETURNING id',
      {'w': workoutId, 'u': userId, 'k': h.uniqueName('img')},
    );
  }

  setUpAll(() async {
    await h.setupDatabase();
    ownerId = await h.seedProfile();
    authorId = await h.seedProfile();
    otherId = await h.seedProfile();
  });

  tearDownAll(h.teardownDatabase);

  group('createComment', () {
    test('persists a comment on a workout target', () async {
      final workoutId = await h.seedWorkout(userId: ownerId);

      final comment = await h.db.createComment(
        authorId: authorId,
        targetType: CommentTarget.workout,
        targetId: workoutId,
        body: 'Nice session',
      );

      expect(comment.authorId, authorId);
      expect(comment.body, 'Nice session');
      expect(comment.targetType, CommentTarget.workout);
      expect(comment.targetId, workoutId);
      expect(comment.editedAt, isNull); // never edited on creation
    });

    // The INSERT routes @targetId into the matching FK column via a CASE per
    // target type; each branch is exercised here so a mis-mapped column surfaces.
    test('routes each polymorphic target type to its column', () async {
      final workoutId = await h.seedWorkout(userId: ownerId, withExercise: true);
      final weId = await workoutExerciseOf(workoutId);
      final setId = await exerciseSetOf(workoutId);
      final imageId = await seedImage(workoutId, ownerId);

      final onExercise = await h.db.createComment(
        authorId: authorId,
        targetType: CommentTarget.workoutExercise,
        targetId: weId,
        body: 'form check',
      );
      expect(onExercise.targetType, CommentTarget.workoutExercise);
      expect(onExercise.targetId, weId);

      final onSet = await h.db.createComment(
        authorId: authorId,
        targetType: CommentTarget.exerciseSet,
        targetId: setId,
        body: 'strong set',
      );
      expect(onSet.targetType, CommentTarget.exerciseSet);
      expect(onSet.targetId, setId);

      final onImage = await h.db.createComment(
        authorId: authorId,
        targetType: CommentTarget.workoutImage,
        targetId: imageId,
        body: 'good pump',
      );
      expect(onImage.targetType, CommentTarget.workoutImage);
      expect(onImage.targetId, imageId);
    });
  });

  group('listComments', () {
    test('returns comments newest-first with limit+1 hasMore and a cursor walk', () async {
      // Dedicated target so sibling cases can't pollute ordering/counts.
      final workoutId = await h.seedWorkout(userId: ownerId);
      final c1 = await h.db.createComment(
        authorId: authorId,
        targetType: CommentTarget.workout,
        targetId: workoutId,
        body: 'first',
      );
      final c2 = await h.db.createComment(
        authorId: authorId,
        targetType: CommentTarget.workout,
        targetId: workoutId,
        body: 'second',
      );
      final c3 = await h.db.createComment(
        authorId: authorId,
        targetType: CommentTarget.workout,
        targetId: workoutId,
        body: 'third',
      );

      final page1 = await h.db.listComments(
        targetType: CommentTarget.workout,
        targetId: workoutId,
        limit: 2,
      );
      expect(page1.items.map((c) => c.id), [c3.id, c2.id]); // uuidv7 → newest first
      expect(page1.hasMore, isTrue);

      final page2 = await h.db.listComments(
        targetType: CommentTarget.workout,
        targetId: workoutId,
        cursor: page1.items.last.id,
        limit: 2,
      );
      expect(page2.items.map((c) => c.id), [c1.id]);
      expect(page2.hasMore, isFalse);
    });

    test('a target with no comments yields an empty page', () async {
      final workoutId = await h.seedWorkout(userId: ownerId);
      final page = await h.db.listComments(
        targetType: CommentTarget.workout,
        targetId: workoutId,
      );
      expect(page.items, isEmpty);
      expect(page.hasMore, isFalse);
    });
  });

  group('editComment', () {
    test('the author updates the body and stamps edited_at', () async {
      final workoutId = await h.seedWorkout(userId: ownerId);
      final comment = await h.db.createComment(
        authorId: authorId,
        targetType: CommentTarget.workout,
        targetId: workoutId,
        body: 'typo',
      );

      final edited = await h.db.editComment(
        commentId: comment.id,
        authorId: authorId,
        body: 'fixed',
      );

      expect(edited.id, comment.id);
      expect(edited.body, 'fixed');
      expect(edited.editedAt, isNotNull);
    });

    test('a non-author editing throws NotFound', () async {
      final workoutId = await h.seedWorkout(userId: ownerId);
      final comment = await h.db.createComment(
        authorId: authorId,
        targetType: CommentTarget.workout,
        targetId: workoutId,
        body: 'mine',
      );

      await expectLater(
        h.db.editComment(commentId: comment.id, authorId: otherId, body: 'hijack'),
        throwsA(isA<NotFound>()),
      );
    });
  });

  group('deleteComment', () {
    test('the author deletes their comment', () async {
      final workoutId = await h.seedWorkout(userId: ownerId);
      final comment = await h.db.createComment(
        authorId: authorId,
        targetType: CommentTarget.workout,
        targetId: workoutId,
        body: 'delete me',
      );

      await h.db.deleteComment(commentId: comment.id, authorId: authorId);

      final page = await h.db.listComments(
        targetType: CommentTarget.workout,
        targetId: workoutId,
      );
      expect(page.items, isEmpty);
    });

    test('a non-author deleting throws NotFound and leaves the comment', () async {
      final workoutId = await h.seedWorkout(userId: ownerId);
      final comment = await h.db.createComment(
        authorId: authorId,
        targetType: CommentTarget.workout,
        targetId: workoutId,
        body: 'keep me',
      );

      await expectLater(
        h.db.deleteComment(commentId: comment.id, authorId: otherId),
        throwsA(isA<NotFound>()),
      );

      final page = await h.db.listComments(
        targetType: CommentTarget.workout,
        targetId: workoutId,
      );
      expect(page.items.single.id, comment.id); // untouched
    });

    test('deleting a missing comment throws NotFound', () async {
      await expectLater(
        h.db.deleteComment(
          commentId: '00000000-0000-7000-8000-000000000000',
          authorId: authorId,
        ),
        throwsA(isA<NotFound>()),
      );
    });
  });

  group('ownerOfTarget', () {
    test('resolves the workout owner for every target type', () async {
      final workoutId = await h.seedWorkout(userId: ownerId, withExercise: true);
      final weId = await workoutExerciseOf(workoutId);
      final setId = await exerciseSetOf(workoutId);
      final imageId = await seedImage(workoutId, ownerId);

      expect(
        await h.db.ownerOfTarget(targetType: CommentTarget.workout, targetId: workoutId),
        ownerId,
      );
      expect(
        await h.db.ownerOfTarget(targetType: CommentTarget.workoutExercise, targetId: weId),
        ownerId,
      );
      expect(
        await h.db.ownerOfTarget(targetType: CommentTarget.exerciseSet, targetId: setId),
        ownerId,
      );
      expect(
        await h.db.ownerOfTarget(targetType: CommentTarget.workoutImage, targetId: imageId),
        ownerId,
      );
    });

    test('returns null for a target that does not exist', () async {
      final owner = await h.db.ownerOfTarget(
        targetType: CommentTarget.workout,
        targetId: '00000000-0000-7000-8000-000000000000',
      );
      expect(owner, isNull);
    });
  });
}

class _Harness extends DatabaseTestBase;
