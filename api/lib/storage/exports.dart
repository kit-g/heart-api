part of 's3.dart';

mixin _Exports on _StorageBase implements ExportStorage {
  /// How long a download link stays good. The object itself expires with the
  /// bucket's lifecycle rule for `exports/`.
  static const _linkLifetime = Duration(minutes: 15);

  @override
  Future<Uri> stash({required String key, required List<int> bytes, required String mimeType}) async {
    final upload = await getUploadUrl(contentBucket, key);
    final client = HttpClient();
    try {
      final request = await client.putUrl(upload);
      request.headers.contentType = ContentType.parse(mimeType);
      request.contentLength = bytes.length;
      request.add(bytes);
      final response = await request.close();
      await response.drain<void>();
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException('export upload failed: ${response.statusCode}', uri: upload);
      }
    } finally {
      client.close();
    }
    return getDownloadUrl(contentBucket, key, expiresIn: _linkLifetime);
  }
}
