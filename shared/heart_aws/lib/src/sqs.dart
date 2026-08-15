part of '../heart_aws.dart';

abstract class SqsApi with Signer {
  new();

  @override
  AWSService get service => .sqs;

  /// Delivers a message to the specified queue.
  ///
  /// Uses the modern SQS JSON protocol.
  Future<String> sendMessage({
    required String queueUrl,
    required String messageBody,
    int? delaySeconds,
    Map<String, dynamic>? messageAttributes,
  }) async {
    final uri = Uri.parse(queueUrl);

    final payload = <String, dynamic>{
      'QueueUrl': queueUrl,
      'MessageBody': messageBody,
      'DelaySeconds': ?delaySeconds,
      'MessageAttributes': ?messageAttributes,
    };

    return post(
      uri: uri,
      headers: {
        'X-Amz-Target': 'AmazonSQS.SendMessage',
        // SQS JSON protocol expects 1.0, and since _sendAwsRequest uses
        // putIfAbsent for 1.1, passing this here will correctly override it.
        AWSHeaders.contentType: 'application/x-amz-json-1.0',
      },
      body: payload,
    );
  }

  Future<String> sendJsonMessage({
    required String queueUrl,
    required Map message,
    int? delaySeconds,
    Map<String, dynamic>? messageAttributes,
  }) {
    return sendMessage(
      queueUrl: queueUrl,
      messageBody: jsonEncode(message),
      delaySeconds: delaySeconds,
      messageAttributes: messageAttributes,
    );
  }
}

class Sqs extends SqsApi {
  @override
  final AWSCredentialsProvider credentialsProvider;

  @override
  final String region;

  new({
    required this.credentialsProvider,
    required this.region,
  });
}
