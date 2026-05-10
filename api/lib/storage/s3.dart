library;

import 'package:aws_common/aws_common.dart';
import 'package:aws_signature_v4/aws_signature_v4.dart';
import 'package:heart/aws/aws.dart';
import 'package:heart_models/heart_models.dart';

import '../models/images.dart';

part 'images.dart';

abstract class _StorageBase extends S3Api {
  String get contentBucket;
}

class Storage extends _StorageBase with _Images implements ApiImageStorageService {
  final AWSCredentialsProvider _credentialsProvider;

  @override
  final String region;
  @override
  final String contentBucket;

  Storage({
    required AWSCredentialsProvider credentialsProvider,
    required this.region,
    required this.contentBucket,
  }) : _credentialsProvider = credentialsProvider;

  @override
  AWSCredentialsProvider get credentialsProvider => _credentialsProvider;
}
