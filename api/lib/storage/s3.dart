library;

import 'dart:io';

import 'package:heart_aws/heart_aws.dart';
import 'package:heart_models/heart_models.dart';

import '../models/exports.dart';
import '../models/images.dart';
import '../models/imports.dart';
import 'keys.dart';

part 'exports.dart';
part 'images.dart';
part 'imports.dart';

abstract class _StorageBase extends S3Api {
  String get contentBucket;

  /// Puts [bytes] at [key] in the content bucket through a presigned upload.
  Future<void> _upload(String key, List<int> bytes, String mimeType) async {
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
        throw HttpException('upload failed: ${response.statusCode}', uri: upload);
      }
    } finally {
      client.close();
    }
  }
}

class Storage extends _StorageBase
    with _Images, _Exports, _Imports
    implements ApiImageStorageService, ExportStorage, ImportStorage {
  final AWSCredentialsProvider _credentialsProvider;

  @override
  final String region;
  @override
  final String contentBucket;

  new({
    required this._credentialsProvider,
    required this.region,
    required this.contentBucket,
  });

  @override
  AWSCredentialsProvider get credentialsProvider => _credentialsProvider;
}
