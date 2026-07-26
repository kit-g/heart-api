@Tags(['db'])
library;

import 'package:heart/models/errors.dart';
import 'package:test/test.dart';

import 'db_test_utility.dart';

/// Integration coverage of the `ApiImageDbService` query strings against a live
/// Postgres: recording images, the gallery listing (user-scoped + limit+1
/// pagination), key lookups, and delete.
///
/// Tagged `db` — skipped by the default `dart test`. Run with:
///   dart test --run-skipped -t db
void main() {
  final h = _Harness();

  late String userId;
  late String otherId;
  late String galleryUserId; // isolated, for pagination
  var keyCount = 0;

  String imageUrl(String key) => 'https://cdn.test/$key';
  String uniqueKey() => 'workouts/itest/${h.token}-${keyCount++}.jpg';

  Future<String> recordImage(String userId, String workoutId, String key) =>
      h.db.recordImage(userId: userId, workoutId: workoutId, key: key, imageUrl: imageUrl).then((i) => i.id);

  setUpAll(() async {
    await h.setupDatabase();
    userId = await h.seedProfile();
    otherId = await h.seedProfile();
    galleryUserId = await h.seedProfile();
  });

  tearDownAll(h.teardownDatabase);

  group('recordImage', () {
    test('inserts and returns the image with its CDN link', () async {
      final workoutId = await h.seedWorkout(userId: userId);
      final key = uniqueKey();

      final image = await h.db.recordImage(userId: userId, workoutId: workoutId, key: key, imageUrl: imageUrl);

      expect(image.workoutId, workoutId);
      expect(image.id, isNotEmpty);
      expect(image.link, imageUrl(key));
    });
  });

  group('getWorkoutImageKeys', () {
    test('returns the keys for one workout only', () async {
      final workoutId = await h.seedWorkout(userId: userId);
      final otherWorkout = await h.seedWorkout(userId: userId);
      final k1 = uniqueKey();
      final k2 = uniqueKey();
      await recordImage(userId, workoutId, k1);
      await recordImage(userId, workoutId, k2);
      await recordImage(userId, otherWorkout, uniqueKey());

      final keys = await h.db.getWorkoutImageKeys(userId: userId, workoutId: workoutId);

      expect(keys, unorderedEquals([k1, k2]));
    });
  });

  group('getUserImageKeys', () {
    test('returns every key the user owns', () async {
      final workoutId = await h.seedWorkout(userId: userId);
      final k1 = uniqueKey();
      final k2 = uniqueKey();
      await recordImage(userId, workoutId, k1);
      await recordImage(userId, workoutId, k2);

      final keys = await h.db.getUserImageKeys(userId: userId);

      expect(keys, containsAll([k1, k2]));
    });
  });

  group('getGallery', () {
    test('lists an isolated user newest-first with limit+1 pagination', () async {
      final workoutId = await h.seedWorkout(userId: galleryUserId);
      final firstId = await recordImage(galleryUserId, workoutId, uniqueKey());
      final secondId = await recordImage(galleryUserId, workoutId, uniqueKey());

      final page1 = await h.db.getGallery(userId: galleryUserId, limit: 1, imageUrl: imageUrl);
      expect(page1.items, hasLength(1));
      expect(page1.hasMore, isTrue);
      expect(page1.items.single.id, secondId); // uuidv7 → newest first

      final page2 = await h.db.getGallery(
        userId: galleryUserId,
        cursor: page1.items.single.id,
        limit: 1,
        imageUrl: imageUrl,
      );
      expect(page2.items.single.id, firstId);
      expect(page2.hasMore, isFalse);
    });

    test('does not surface another user\'s images', () async {
      final otherWorkout = await h.seedWorkout(userId: otherId);
      final otherImageId = await recordImage(otherId, otherWorkout, uniqueKey());

      final page = await h.db.getGallery(userId: userId, limit: 100, imageUrl: imageUrl);

      expect(page.items.map((i) => i.id), isNot(contains(otherImageId)));
    });
  });

  group('deleteImageRecord', () {
    test('removes the record', () async {
      final workoutId = await h.seedWorkout(userId: userId);
      final key = uniqueKey();
      await recordImage(userId, workoutId, key);

      await h.db.deleteImageRecord(userId: userId, workoutId: workoutId, key: key);

      final keys = await h.db.getWorkoutImageKeys(userId: userId, workoutId: workoutId);
      expect(keys, isNot(contains(key)));
    });

    test('throws NotFound for a key that is not there', () async {
      final workoutId = await h.seedWorkout(userId: userId);
      await expectLater(
        h.db.deleteImageRecord(userId: userId, workoutId: workoutId, key: 'nope-${h.token}.jpg'),
        throwsA(isA<NotFound>()),
      );
    });
  });
}

class _Harness extends DatabaseTestBase {}
