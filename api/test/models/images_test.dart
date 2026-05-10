import 'package:heart/models/images.dart';
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

  group('GalleryResponse', () {
    test('toMap includes cursor when set', () {
      final response = const GalleryResponse(images: [], cursor: 'next');
      expect(response.toMap()['cursor'], equals('next'));
    });

    test('toMap omits cursor when null', () {
      final response = const GalleryResponse(images: []);
      expect(response.toMap().containsKey('cursor'), isFalse);
    });

    test('toMap serializes images via toRow()', () {
      final image = WorkoutImage.fromJson({
        'id': 'img_1',
        'workoutId': 'w_1',
        'key': '/workouts/abc/img_1.jpg',
        'url': 'https://cdn/workouts/abc/img_1.jpg',
      });
      final response = GalleryResponse(images: [image]);

      final images = response.toMap()['images'] as List;
      expect(images, hasLength(1));
      expect((images.first as Map)['id'], equals('img_1'));
      expect((images.first as Map)['workoutId'], equals('w_1'));
    });

    test('iterates over its images', () {
      final image = WorkoutImage.fromJson({
        'id': 'img_1',
        'workoutId': 'w_1',
        'key': '/k',
        'url': 'https://cdn/k',
      });
      final response = GalleryResponse(images: [image]);

      expect(response.toList(), hasLength(1));
      expect(response.first.id, 'img_1');
    });
  });
}