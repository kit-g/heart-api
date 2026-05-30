import 'package:heart/events/account_deletion.dart';
import 'package:heart/globals/config.dart';
import 'package:heart/middleware/database.dart';
import 'package:heart/middleware/events.dart';
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
    late MockEventPublisher publisher;
    late MockAppConfig config;
    late Request request;

    setUp(() {
      imageDb = MockApiImageDbService();
      imageStorage = MockApiImageStorageService();
      profileService = MockApiProfileService();
      publisher = MockEventPublisher();
      config = MockAppConfig();
      when(config.firebaseEventsQueueUrl).thenReturn('https://sqs.test/heart-firebase-events');
      when(
        publisher.publish(queueUrl: anyNamed('queueUrl'), message: anyNamed('message')),
      ).thenAnswer((_) async {});

      request = _request()
        ..imageDbService = imageDb
        ..imageStorageService = imageStorage
        ..profileService = profileService
        ..config = config
        ..events = publisher;
    });

    test('deletes profile and fans out to firebase when user has no images', () async {
      when(imageDb.getUserImageKeys(userId: 'u1')).thenAnswer((_) async => []);
      when(profileService.deleteAccount(userId: 'u1')).thenAnswer((_) async {});

      await accountDeletion(request, 'u1');

      verify(imageDb.getUserImageKeys(userId: 'u1')).called(1);
      verify(profileService.deleteAccount(userId: 'u1')).called(1);
      verifyNever(imageStorage.deleteObject(key: anyNamed('key')));
      verify(
        publisher.publish(
          queueUrl: 'https://sqs.test/heart-firebase-events',
          message: {'type': 'account.delete', 'uid': 'u1'},
        ),
      ).called(1);
    });

    test('deletes each S3 image, then profile, then fans out to firebase', () async {
      when(
        imageDb.getUserImageKeys(userId: 'u1'),
      ).thenAnswer(
        (_) async => [
          'workouts/abc/img1.jpg',
          'workouts/abc/img2.jpg',
        ],
      );
      when(imageStorage.deleteObject(key: anyNamed('key'))).thenAnswer((_) async {});
      when(profileService.deleteAccount(userId: 'u1')).thenAnswer((_) async {});

      await accountDeletion(request, 'u1');

      verifyInOrder([
        imageStorage.deleteObject(key: 'workouts/abc/img1.jpg'),
        imageStorage.deleteObject(key: 'workouts/abc/img2.jpg'),
        profileService.deleteAccount(userId: 'u1'),
        publisher.publish(queueUrl: anyNamed('queueUrl'), message: anyNamed('message')),
      ]);
    });

    test('does not delete profile or fan out if S3 cleanup throws', () async {
      when(imageDb.getUserImageKeys(userId: 'u1')).thenAnswer((_) async => ['workouts/x.jpg']);
      when(imageStorage.deleteObject(key: 'workouts/x.jpg')).thenThrow(Exception('S3 down'));

      expect(
        () => accountDeletion(request, 'u1'),
        throwsA(isA<Exception>()),
      );

      await pumpEventQueue();
      verifyNever(profileService.deleteAccount(userId: 'u1'));
      verifyNever(publisher.publish(queueUrl: anyNamed('queueUrl'), message: anyNamed('message')));
    });
  });
}
