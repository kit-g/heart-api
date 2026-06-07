import 'package:heart/globals/config.dart';
import 'package:heart/middleware/s3.dart';
import 'package:relic/relic.dart';

/// Consumes an `exercise.asset.processed` event off the API's events queue.
///
/// The assets Lambda (Python + Pillow) has already rendered the thumbnail,
/// measured dimensions, and written both objects to the content bucket. It
/// stays env-agnostic and sends only S3 keys; this handler turns each into a
/// `{link, width, height}` blob via [AppConfig.cdnAssetUrl] — the single,
/// env-aware place CDN links are built (it reads `MEDIA_DISTRIBUTION`) — and
/// persists them onto the matching global exercise (user_id IS NULL), keyed by
/// name. The DB lives behind the API, so credentials stay in this Lambda only.
Future<void> exerciseAssetProcessed(Request request, Map event) async {
  Map<String, dynamic> media(Object? descriptor) {
    return switch (descriptor) {
      {'key': String key, 'width': int width, 'height': int height} => {
        'link': request.config.cdnAssetUrl(key),
        'width': width,
        'height': height,
      },
      _ => throw ArgumentError.value(descriptor, 'media', 'malformed media descriptor'),
    };
  }

  switch (event) {
    case {
      'name': String name,
      'asset': final asset,
      'thumbnail': final thumbnail,
    }:
      await request.exerciseService.setExerciseMedia(
        name: name,
        asset: media(asset),
        thumbnail: media(thumbnail),
      );
    default:
      throw ArgumentError.value(event, 'event', 'malformed exercise.asset.processed');
  }
}
