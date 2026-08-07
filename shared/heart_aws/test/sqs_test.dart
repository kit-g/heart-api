import 'dart:convert';

import 'package:heart_aws/heart_aws.dart';
import 'package:test/test.dart';

const _queueUrl = 'https://sqs.us-east-1.amazonaws.com/123456789012/my-queue';

/// Captures the requests [SqsApi] builds instead of sending them to AWS.
class _RecordingSqs extends SqsApi {
  @override
  final String region = 'us-east-1';

  @override
  final AWSCredentialsProvider credentialsProvider = const StaticCredentialsProvider(
    AWSCredentials('AKIDEXAMPLE', 'secret'),
  );

  final posts = <({Uri uri, Map<String, String>? headers, Map<String, dynamic>? body})>[];

  @override
  Future<String> post({required Uri uri, Map<String, String>? headers, Map<String, dynamic>? body}) async {
    posts.add((uri: uri, headers: headers, body: body));
    return '{"MessageId":"message-1"}';
  }
}

void main() {
  group('sendMessage', () {
    test('posts to the queue URL with the SQS JSON protocol headers', () async {
      final sqs = _RecordingSqs();
      await sqs.sendMessage(queueUrl: _queueUrl, messageBody: 'hello');

      final call = sqs.posts.single;
      expect(call.uri, Uri.parse(_queueUrl));
      expect(call.headers, {
        'X-Amz-Target': 'AmazonSQS.SendMessage',
        AWSHeaders.contentType: 'application/x-amz-json-1.0',
      });
    });

    test('builds a payload with only the required keys by default', () async {
      final sqs = _RecordingSqs();
      await sqs.sendMessage(queueUrl: _queueUrl, messageBody: 'hello');

      expect(sqs.posts.single.body, {
        'QueueUrl': _queueUrl,
        'MessageBody': 'hello',
      });
    });

    test('includes DelaySeconds and MessageAttributes when given', () async {
      final sqs = _RecordingSqs();
      final attributes = {
        'Kind': {'DataType': 'String', 'StringValue': 'greeting'},
      };
      await sqs.sendMessage(
        queueUrl: _queueUrl,
        messageBody: 'hello',
        delaySeconds: 30,
        messageAttributes: attributes,
      );

      expect(sqs.posts.single.body, {
        'QueueUrl': _queueUrl,
        'MessageBody': 'hello',
        'DelaySeconds': 30,
        'MessageAttributes': attributes,
      });
    });

    test('returns the raw response body', () async {
      expect(await _RecordingSqs().sendMessage(queueUrl: _queueUrl, messageBody: 'hello'), '{"MessageId":"message-1"}');
    });
  });

  group('sendJsonMessage', () {
    test('JSON-encodes the message as the body', () async {
      final sqs = _RecordingSqs();
      final message = {
        'type': 'ping',
        'payload': {'id': 7},
      };
      await sqs.sendJsonMessage(queueUrl: _queueUrl, message: message);

      final body = sqs.posts.single.body!;
      expect(body['MessageBody'], jsonEncode(message));
      expect(jsonDecode(body['MessageBody'] as String), message);
    });

    test('forwards delaySeconds and messageAttributes', () async {
      final sqs = _RecordingSqs();
      await sqs.sendJsonMessage(
        queueUrl: _queueUrl,
        message: const {'a': 1},
        delaySeconds: 5,
        messageAttributes: const {
          'K': {'DataType': 'String', 'StringValue': 'v'},
        },
      );

      final body = sqs.posts.single.body!;
      expect(body['DelaySeconds'], 5);
      expect(body['MessageAttributes'], const {
        'K': {'DataType': 'String', 'StringValue': 'v'},
      });
    });
  });
}
