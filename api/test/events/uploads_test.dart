import 'package:heart/events/uploads.dart';
import 'package:heart/globals/config.dart';
import 'package:heart/middleware/database.dart';
import 'package:heart/middleware/s3.dart';
import 'package:heart_models/heart_models.dart';
import 'package:mockito/mockito.dart';
import 'package:relic_core/relic_core.dart';
import 'package:test/test.dart';

import '../mocks.mocks.dart';

Request _request() => RequestInternal.create(Method.post, Uri.parse('http://localhost/events'), Object());

void main() {
  late MockApiImageDbService imageDb;
  late MockApiImageStorageService imageStorage;
  late MockApiProfileService profileService;
  late MockAppConfig config;
  late Request request;
  late List<Object> errors;

  void onError(Object error, [StackTrace? st]) => errors.add(error);

  setUp(() {
    imageDb = MockApiImageDbService();
    imageStorage = MockApiImageStorageService();
    profileService = MockApiProfileService();
    config = MockAppConfig();
    errors = [];

    when(config.cdnAssetUrl(any)).thenAnswer((inv) => 'https://cdn.example/${inv.positionalArguments.first}');
    when(imageStorage.copyObject(fromKey: anyNamed('fromKey'), toKey: anyNamed('toKey'))).thenAnswer((_) async {});
    when(imageStorage.deleteObject(key: anyNamed('key'))).thenAnswer((_) async {});
    final dummyImage = WorkoutImage.fromJson({
      'id': 'i', 'workoutId': 'w', 'key': '/k', 'url': 'https://cdn/k',
    });
    final dummyUser = User(id: 'u1');
    when(imageDb.recordImage(
      userId: anyNamed('userId'),
      workoutId: anyNamed('workoutId'),
      key: anyNamed('key'),
      imageUrl: anyNamed('imageUrl'),
    )).thenAnswer((_) async => dummyImage);
    when(profileService.updateAvatarUrl(
      userId: anyNamed('userId'),
      avatarUrl: anyNamed('avatarUrl'),
    )).thenAnswer((_) async => dummyUser);

    request = _request()
      ..imageDbService = imageDb
      ..imageStorageService = imageStorage
      ..profileService = profileService
      ..config = config;
  });

  group('imageUpload — workout image branch', () {
    const bucket = 'content-bucket';
    const uploadKey = 'uploads/abc123.jpg';

    test('copies upload to workouts/<hash>/<imageId>.<ext>, deletes upload, records image', () async {
      when(imageStorage.getObjectTagging(bucket, uploadKey)).thenAnswer((_) async => {
        'user-id': 'u1',
        'workout-id': 'w1',
        'image-id': 'img1',
      });

      await imageUpload(request, bucket, uploadKey, onError: onError);

      verifyInOrder([
        imageStorage.copyObject(
          fromKey: uploadKey,
          toKey: argThat(matches(r'^workouts/[a-f0-9]{16}/img1\.jpg$'), named: 'toKey'),
        ),
        imageStorage.deleteObject(key: uploadKey),
        imageDb.recordImage(
          userId: 'u1',
          workoutId: 'w1',
          key: argThat(matches(r'^workouts/[a-f0-9]{16}/img1\.jpg$'), named: 'key'),
          imageUrl: anyNamed('imageUrl'),
        ),
      ]);
      expect(errors, isEmpty);
    });

    test('uses .jpg as default extension when upload key has no extension', () async {
      when(imageStorage.getObjectTagging(bucket, 'uploads/abc123')).thenAnswer((_) async => {
        'user-id': 'u1',
        'workout-id': 'w1',
        'image-id': 'img1',
      });

      await imageUpload(request, bucket, 'uploads/abc123', onError: onError);

      verify(imageStorage.copyObject(
        fromKey: 'uploads/abc123',
        toKey: argThat(endsWith('.jpg'), named: 'toKey'),
      )).called(1);
    });

    test('skips when any required tag is missing', () async {
      when(imageStorage.getObjectTagging(bucket, uploadKey)).thenAnswer((_) async => {
        'user-id': 'u1',
        'workout-id': 'w1',
        // image-id missing
      });

      await imageUpload(request, bucket, uploadKey, onError: onError);

      verifyNever(imageStorage.copyObject(fromKey: anyNamed('fromKey'), toKey: anyNamed('toKey')));
      verifyNever(imageDb.recordImage(
        userId: anyNamed('userId'),
        workoutId: anyNamed('workoutId'),
        key: anyNamed('key'),
        imageUrl: anyNamed('imageUrl'),
      ));
      expect(errors, isEmpty);
    });
  });

  group('imageUpload — avatar branch', () {
    const bucket = 'content-bucket';
    const uploadKey = 'uploads/avatar-u1';

    test('copies to avatars/<userId>, deletes upload, updates avatar URL', () async {
      when(imageStorage.getObjectTagging(bucket, uploadKey)).thenAnswer((_) async => {
        'kind': 'avatar',
        'user-id': 'u1',
      });

      await imageUpload(request, bucket, uploadKey, onError: onError);

      verifyInOrder([
        imageStorage.copyObject(fromKey: uploadKey, toKey: 'avatars/u1'),
        imageStorage.deleteObject(key: uploadKey),
        profileService.updateAvatarUrl(
          userId: 'u1',
          avatarUrl: 'https://cdn.example/avatars/u1',
        ),
      ]);
      expect(errors, isEmpty);
    });

    test('skips when user-id is empty', () async {
      when(imageStorage.getObjectTagging(bucket, uploadKey)).thenAnswer((_) async => {
        'kind': 'avatar',
        'user-id': '',
      });

      await imageUpload(request, bucket, uploadKey, onError: onError);

      verifyNever(imageStorage.copyObject(fromKey: anyNamed('fromKey'), toKey: anyNamed('toKey')));
      verifyNever(profileService.updateAvatarUrl(userId: anyNamed('userId'), avatarUrl: anyNamed('avatarUrl')));
    });
  });

  group('imageUpload — unknown tag shape', () {
    test('skips silently with no errors', () async {
      when(imageStorage.getObjectTagging('b', 'k')).thenAnswer((_) async => {'kind': 'something-else'});

      await imageUpload(request, 'b', 'k', onError: onError);

      verifyNever(imageStorage.copyObject(fromKey: anyNamed('fromKey'), toKey: anyNamed('toKey')));
      verifyNever(imageStorage.deleteObject(key: anyNamed('key')));
      expect(errors, isEmpty);
    });
  });
}
