import 'package:heart/globals/config.dart';
import 'package:heart/globals/globals.dart';
import 'package:heart/middleware/database.dart';
import 'package:heart/middleware/s3.dart';
import 'package:heart/models/errors.dart';
import 'package:heart/routes/images.dart';
import 'package:heart_models/heart_models.dart';
import 'package:mockito/mockito.dart';
import 'package:relic_core/relic_core.dart';
import 'package:test/test.dart';

import '../helpers/request.dart';
import '../mocks.mocks.dart';

const _meId = 'u1';

WorkoutImage _fakeImage(String id) => WorkoutImage.fromJson({
  'id': id,
  'workoutId': 'w-1',
  'key': '/workouts/abc/$id.jpg',
  'url': 'https://cdn/workouts/abc/$id.jpg',
});

void main() {
  late MockApiImageDbService imageDb;
  late MockAppConfig config;
  late MockApiWorkoutService workouts;
  late MockApiImageStorageService imageStorage;

  setUp(() {
    imageDb = MockApiImageDbService();
    config = MockAppConfig();
    workouts = MockApiWorkoutService();
    imageStorage = MockApiImageStorageService();
  });

  Request wire(Request req) => req
    ..user = User(id: _meId)
    ..config = config
    ..imageDbService = imageDb
    ..workoutsService = workouts
    ..imageStorageService = imageStorage;

  void stubGetGallery(Page<WorkoutImage> page) {
    when(
      imageDb.getGallery(
        userId: anyNamed('userId'),
        imageUrl: anyNamed('imageUrl'),
        cursor: anyNamed('cursor'),
        limit: anyNamed('limit'),
      ),
    ).thenAnswer((_) async => page);
  }

  Request getReq({Map<String, String> query = const {}}) =>
      wire(bareRequest(method: Method.get, path: '/workouts/images', query: query));

  /// The presign used to hand out a URL for any id, so an upload against a
  /// workout the caller does not have succeeded, transferred, and only failed
  /// later in the event handler on the `workout_id` FK — after the object had
  /// been copied and its source deleted. Refuse first instead.
  group('presignWorkoutImage — the workout must exist', () {
    setUp(() {
      when(config.allowedMimeTypes).thenReturn(const {'image/jpeg', 'image/png'});
    });

    Request presignReq(String workoutId) => wire(
      jsonRequest(
        method: Method.put,
        path: '/workouts/$workoutId/images',
        body: const {'mimeType': 'image/jpeg'},
      ),
    );

    test('a workout the caller does not have is a NotFound, and nothing is presigned', () async {
      when(
        workouts.getWorkout(
          userId: anyNamed('userId'),
          workoutId: anyNamed('workoutId'),
          imageUrl: anyNamed('imageUrl'),
        ),
      ).thenThrow(const NotFound(type: 'Workout', id: 'w-missing'));

      await expectLater(
        presignWorkoutImageById(presignReq('w-missing'), 'w-missing'),
        throwsA(isA<NotFound>()),
      );

      verifyNever(
        imageStorage.presignUpload(
          key: anyNamed('key'),
          mimeType: anyNamed('mimeType'),
          tags: anyNamed('tags'),
        ),
      );
    });
  });

  group('getGallery', () {
    test('omits cursor when there is no next page', () async {
      stubGetGallery(Page(items: [_fakeImage('img-1')], hasMore: false));

      final result = await getGallery(getReq());

      expect(result.toMap()['images'], hasLength(1));
      expect(result.toMap().containsKey('cursor'), isFalse);
    });

    test('emits the last image id as cursor when there is a next page', () async {
      stubGetGallery(Page(items: [_fakeImage('img-1'), _fakeImage('img-2')], hasMore: true));

      final result = await getGallery(getReq());

      expect(result.toMap()['cursor'], 'img-2');
    });

    test('clamps limit to the max and passes the cursor through', () async {
      stubGetGallery(const Page(items: [], hasMore: false));

      await getGallery(getReq(query: {'limit': '999', 'cursor': 'img-9'}));

      verify(
        imageDb.getGallery(
          userId: argThat(equals(_meId), named: 'userId'),
          imageUrl: anyNamed('imageUrl'),
          cursor: argThat(equals('img-9'), named: 'cursor'),
          limit: argThat(equals(100), named: 'limit'),
        ),
      ).called(1);
    });

    test('defaults to a limit of 20 with no cursor when unspecified', () async {
      stubGetGallery(const Page(items: [], hasMore: false));

      await getGallery(getReq());

      verify(
        imageDb.getGallery(
          userId: argThat(equals(_meId), named: 'userId'),
          imageUrl: anyNamed('imageUrl'),
          cursor: argThat(isNull, named: 'cursor'),
          limit: argThat(equals(20), named: 'limit'),
        ),
      ).called(1);
    });
  });
}
