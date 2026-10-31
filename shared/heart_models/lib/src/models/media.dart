import 'dart:typed_data';

/// Agnostic abstraction of an image or a video
abstract interface class Media {
  /// local bytes
  Uint8List? get bytes;

  /// Where the image is served from.
  String? get link;

  /// The image's id.
  String get id;

  /// possibly createdAt timestamp
  DateTime? get timestamp;
}
