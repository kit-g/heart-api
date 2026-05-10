import 'dart:typed_data';

/// Agnostic abstraction of an image or a video
abstract interface class Media {
  /// local bytes
  Uint8List? get bytes;

  /// remote URL
  String? get link;

  /// some sort of identifier
  String get id;

  /// possibly createdAt timestamp
  DateTime? get timestamp;
}
