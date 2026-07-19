import 'package:heart/globals/config.dart';
import 'package:heart/globals/globals.dart';
import 'package:heart/middleware/database.dart';
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

  setUp(() {
    imageDb = MockApiImageDbService();
    config = MockAppConfig();
  });

  Request wire(Request req) => req
    ..user = User(id: _meId)
    ..config = config
    ..imageDbService = imageDb;

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
