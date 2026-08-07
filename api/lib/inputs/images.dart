part of 'inputs.dart';

const _defaultImageMimeType = 'image/jpeg';

extension on Map<String, dynamic> {
  /// Optional `mimeType`, defaulted to JPEG and checked against the allowlist.
  String imageMimeType(Iterable<String> allowed) {
    final mimeType = stringOrNull('mimeType') ?? _defaultImageMimeType;
    if (!allowed.contains(mimeType)) {
      throw BadRequest(reason: 'Unsupported image type: $mimeType. Allowed types: ${allowed.join(', ')}');
    }
    return mimeType;
  }
}

class WorkoutImagePresignIn {
  final String mimeType;
  final String ext;

  const WorkoutImagePresignIn._({required this.mimeType, required this.ext});

  static Future<WorkoutImagePresignIn> fromRequest(Request req) async {
    final json = await req.json();
    final mimeType = json.imageMimeType(req.config.allowedMimeTypes);
    return WorkoutImagePresignIn._(
      mimeType: mimeType,
      ext: extensionFromMime(mimeType) ?? 'jpg',
    );
  }
}

class WorkoutImageDeleteQuery {
  final String key;

  const WorkoutImageDeleteQuery._({required this.key});

  factory WorkoutImageDeleteQuery.fromRequest(Request req) {
    return WorkoutImageDeleteQuery._(key: req.queryParameters.raw.string('key'));
  }
}
