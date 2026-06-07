import 'package:heart/events/exercise_asset.dart';
import 'package:heart/globals/config.dart';
import 'package:heart/middleware/s3.dart';
import 'package:mockito/mockito.dart';
import 'package:relic_core/relic_core.dart';
import 'package:test/test.dart';

import '../mocks.mocks.dart';

Request _request() => RequestInternal.create(.post, Uri.parse('http://localhost/events'), Object());

void main() {
  late MockExerciseService exercises;
  late MockAppConfig config;
  late Request request;

  setUp(
    () {
      exercises = MockExerciseService();
      config = MockAppConfig();

      // Mirrors the real cdnAssetUrl: prefixes the (env-aware) media domain.
      when(config.cdnAssetUrl(any)).thenAnswer((inv) => 'https://cdn.example/${inv.positionalArguments.first}');
      when(
        exercises.setExerciseMedia(
          name: anyNamed('name'),
          asset: anyNamed('asset'),
          thumbnail: anyNamed('thumbnail'),
        ),
      ).thenAnswer((_) async {});

      request = _request()
        ..exerciseService = exercises
        ..config = config;
    },
  );

  group(
    'exerciseAssetProcessed',
    () {
      test('builds env-aware links from keys and persists them with dimensions', () async {
        await exerciseAssetProcessed(
          request,
          {
            'type': 'exercise.asset.processed',
            'name': 'Bicycle Crunch',
            'asset': {'key': 'exercises/Bicycle Crunch/asset.gif', 'width': 480, 'height': 360},
            'thumbnail': {'key': 'exercises/Bicycle Crunch/thumbnail.jpg', 'width': 320, 'height': 240},
          },
        );

        verify(
          exercises.setExerciseMedia(
            name: 'Bicycle Crunch',
            asset: {
              'link': 'https://cdn.example/exercises/Bicycle Crunch/asset.gif',
              'width': 480,
              'height': 360,
            },
            thumbnail: {
              'link': 'https://cdn.example/exercises/Bicycle Crunch/thumbnail.jpg',
              'width': 320,
              'height': 240,
            },
          ),
        ).called(1);
      });

      test(
        'throws on a malformed event instead of silently dropping it',
        () async {
          expect(
            () => exerciseAssetProcessed(request, {
              'type': 'exercise.asset.processed',
              'name': 'Bicycle Crunch',
              // asset / thumbnail missing
            }),
            throwsArgumentError,
          );
          verifyNever(
            exercises.setExerciseMedia(
              name: anyNamed('name'),
              asset: anyNamed('asset'),
              thumbnail: anyNamed('thumbnail'),
            ),
          );
        },
      );

      test(
        'throws when a media descriptor is missing its dimensions',
        () async {
          expect(
            () => exerciseAssetProcessed(
              request,
              {
                'type': 'exercise.asset.processed',
                'name': 'Bicycle Crunch',
                'asset': {'key': 'exercises/Bicycle Crunch/asset.gif'},
                'thumbnail': {'key': 'exercises/Bicycle Crunch/thumbnail.jpg', 'width': 320, 'height': 240},
              },
            ),
            throwsArgumentError,
          );
          verifyNever(
            exercises.setExerciseMedia(
              name: anyNamed('name'),
              asset: anyNamed('asset'),
              thumbnail: anyNamed('thumbnail'),
            ),
          );
        },
      );
    },
  );
}
