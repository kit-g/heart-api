import 'package:heart/events/account_deletion.dart';
import 'package:heart/middleware/database.dart';
import 'package:heart/middleware/s3.dart';
import 'package:mockito/mockito.dart';
import 'package:relic_core/relic_core.dart';
import 'package:test/test.dart';

import '../mocks.mocks.dart';

Request _request() => RequestInternal.create(Method.post, Uri.parse('http://localhost/events'), Object());

void main() {
  group('accountDeletion', () {
    late MockApiImageDbService imageDb;
    late MockApiImageStorageService imageStorage;
    late MockApiProfileService profileService;
    late Request request;

    setUp(() {
      imageDb = MockApiImageDbService();
      imageStorage = MockApiImageStorageService();
      profileService = MockApiProfileService();

      request = _request()
        ..imageDbService = imageDb
        ..imageStorageService = imageStorage
        ..profileService = profileService;
    });

    test('deletes profile when user has no images', () async {
      when(imageDb.getUserImageKeys(userId: 'u1')).thenAnswer((_) async => []);
      when(profileService.deleteAccount(userId: 'u1')).thenAnswer((_) async {});

      await accountDeletion(request, 'u1');

      verify(imageDb.getUserImageKeys(userId: 'u1')).called(1);
      verify(profileService.deleteAccount(userId: 'u1')).called(1);
      verifyNever(imageStorage.deleteObject(key: anyNamed('key')));
    });

    test('deletes each S3 image before deleting profile', () async {
      when(imageDb.getUserImageKeys(userId: 'u1')).thenAnswer((_) async => [
        'workouts/abc/img1.jpg',
        'workouts/abc/img2.jpg',
      ]);
      when(imageStorage.deleteObject(key: anyNamed('key'))).thenAnswer((_) async {});
      when(profileService.deleteAccount(userId: 'u1')).thenAnswer((_) async {});

      await accountDeletion(request, 'u1');

      verifyInOrder([
        imageStorage.deleteObject(key: 'workouts/abc/img1.jpg'),
        imageStorage.deleteObject(key: 'workouts/abc/img2.jpg'),
        profileService.deleteAccount(userId: 'u1'),
      ]);
    });

    test('does not delete profile if S3 cleanup throws', () async {
      when(imageDb.getUserImageKeys(userId: 'u1')).thenAnswer((_) async => ['workouts/x.jpg']);
      when(imageStorage.deleteObject(key: 'workouts/x.jpg')).thenThrow(Exception('S3 down'));

      expect(
        () => accountDeletion(request, 'u1'),
        throwsA(isA<Exception>()),
      );

      await pumpEventQueue();
      verifyNever(profileService.deleteAccount(userId: 'u1'));
    });
  });
}
