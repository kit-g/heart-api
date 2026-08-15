part of '../heart_aws.dart';

abstract class SnsApi with Signer {
  new();

  @override
  AWSService get service => .sns;

  Future<void> publish({
    required String topicArn,
    required String message,
    String? subject,
  }) async {
    final uri = Uri.https('sns.$region.amazonaws.com', '/');

    final payload = <String, dynamic>{
      'TopicArn': topicArn,
      'Message': message,
      'Subject': ?subject,
    };

    await post(
      uri: uri,
      headers: {
        'X-Amz-Target': 'AmazonSimpleNotificationService.Publish',
        AWSHeaders.contentType: 'application/x-amz-json-1.0',
      },
      body: payload,
    );
  }
}

class Sns extends SnsApi {
  @override
  final AWSCredentialsProvider credentialsProvider;

  @override
  final String region;

  new({
    required this.credentialsProvider,
    required this.region,
  });
}
