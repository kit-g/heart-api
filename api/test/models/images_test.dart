import 'package:heart/models/images.dart';
import 'package:heart/models/pagination.dart';
import 'package:heart_models/heart_models.dart';
import 'package:test/test.dart';

void main() {
  group('PresignedUploadResponse', () {
    test('toMap includes url, fields, destinationUrl, key', () {
      final response = const PresignedUploadResponse(
        preSignedUrl: (
          url: 'https://bucket.s3.amazonaws.com/',
          fields: {'key': 'uploads/avatar-u1', 'policy': 'opaque'},
        ),
        destinationUrl: 'https://cdn.example/avatars/u1',
        key: 'avatars/u1',
      );

      final map = response.toMap();
      expect(map['url'], equals('https://bucket.s3.amazonaws.com/'));
      expect(map['destinationUrl'], equals('https://cdn.example/avatars/u1'));
      expect(map['key'], equals('avatars/u1'));
      expect(map['fields'], containsPair('key', 'uploads/avatar-u1'));
      expect(map['fields'], containsPair('policy', 'opaque'));
    });
  });

  group('gallery Paginated<WorkoutImage>', () {
    WorkoutImage image(String id) => WorkoutImage.fromJson({
      'id': id,
      'workoutId': 'w_1',
      'key': '/workouts/abc/$id.jpg',
      'url': 'https://cdn/workouts/abc/$id.jpg',
    });

    Paginated<WorkoutImage> gallery(Page<WorkoutImage> page) =>
        Paginated<WorkoutImage>.from(page, itemsKey: 'images', cursorOf: (i) => i.id);

    test('emits the last id as cursor when there is a next page', () {
      final response = gallery(Page(items: [image('img_1'), image('img_2')], hasMore: true));
      expect(response.toMap()['cursor'], equals('img_2'));
    });

    test('omits cursor when the list is exhausted', () {
      final response = gallery(Page(items: [image('img_1')], hasMore: false));
      expect(response.toMap().containsKey('cursor'), isFalse);
    });

    test('serializes images via toMap()', () {
      final response = gallery(Page(items: [image('img_1')], hasMore: false));

      final images = response.toMap()['images'] as List;
      expect(images, hasLength(1));
      expect((images.first as Map)['id'], equals('img_1'));
      expect((images.first as Map)['workoutId'], equals('w_1'));
    });

    test('iterates over its images', () {
      final response = gallery(Page(items: [image('img_1')], hasMore: false));

      expect(response.toList(), hasLength(1));
      expect(response.first.id, 'img_1');
    });
  });
}
