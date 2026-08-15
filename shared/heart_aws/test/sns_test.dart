import 'package:heart_aws/heart_aws.dart';
import 'package:test/test.dart';

const _topicArn = 'arn:aws:sns:us-east-1:123456789012:my-topic';

/// Captures the requests [SnsApi] builds instead of sending them to AWS.
class _RecordingSns extends SnsApi {
  @override
  final String region;

  @override
  final AWSCredentialsProvider credentialsProvider = const StaticCredentialsProvider(
    AWSCredentials('AKIDEXAMPLE', 'secret'),
  );

  new({this.region = 'us-east-1'});

  final posts = <({Uri uri, Map<String, String>? headers, Map<String, dynamic>? body})>[];

  @override
  Future<String> post({required Uri uri, Map<String, String>? headers, Map<String, dynamic>? body}) async {
    posts.add((uri: uri, headers: headers, body: body));
    return '{}';
  }
}

void main() {
  group('publish', () {
    test('posts to the regional SNS endpoint with the Publish target header', () async {
      final sns = _RecordingSns();
      await sns.publish(topicArn: _topicArn, message: 'hello');

      final call = sns.posts.single;
      expect(call.uri, Uri.https('sns.us-east-1.amazonaws.com', '/'));
      expect(call.headers, {
        'X-Amz-Target': 'AmazonSimpleNotificationService.Publish',
        AWSHeaders.contentType: 'application/x-amz-json-1.0',
      });
    });

    test('uses the configured region in the endpoint', () async {
      final sns = _RecordingSns(region: 'eu-central-1');
      await sns.publish(topicArn: _topicArn, message: 'hello');
      expect(sns.posts.single.uri.host, 'sns.eu-central-1.amazonaws.com');
    });

    test('omits Subject from the payload when not given', () async {
      final sns = _RecordingSns();
      await sns.publish(topicArn: _topicArn, message: 'hello');

      expect(sns.posts.single.body, {
        'TopicArn': _topicArn,
        'Message': 'hello',
      });
    });

    test('includes Subject in the payload when given', () async {
      final sns = _RecordingSns();
      await sns.publish(topicArn: _topicArn, message: 'hello', subject: 'Greeting');

      expect(sns.posts.single.body, {
        'TopicArn': _topicArn,
        'Message': 'hello',
        'Subject': 'Greeting',
      });
    });
  });
}
