library;

import 'dart:io';

import 'package:heart_aws/heart_aws.dart';
import 'package:heart_models/heart_models.dart';

import '../models/exports.dart';
import '../models/images.dart';

part 'exports.dart';
part 'images.dart';

abstract class _StorageBase extends S3Api {
  String get contentBucket;
}

class Storage extends _StorageBase with _Images, _Exports implements ApiImageStorageService, ExportStorage {
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
