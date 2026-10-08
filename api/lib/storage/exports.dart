part of 's3.dart';

mixin _Exports on _StorageBase implements ExportStorage {
  /// How long a download link stays good. The object itself expires with the
  /// bucket's lifecycle rule for `exports/`.
  static const _linkLifetime = Duration(minutes: 15);

  @override
  Future<Uri> stash({required String key, required List<int> bytes, required String mimeType}) async {
    await _upload(key, bytes, mimeType);
    return getDownloadUrl(contentBucket, key, expiresIn: _linkLifetime);
  }
}
