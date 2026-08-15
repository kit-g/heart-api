import 'package:heart_aws/heart_aws.dart';
import 'package:test/test.dart';

const _targetArn = 'arn:aws:lambda:us-east-1:123456789012:function:my-fn';
const _roleArn = 'arn:aws:iam::123456789012:role/scheduler-role';

/// Captures the requests [SchedulerApi] builds instead of sending them to AWS,
/// and can simulate AWS error responses.
class _RecordingScheduler extends SchedulerApi {
  @override
  final String region = 'us-east-1';

  @override
  final AWSCredentialsProvider credentialsProvider = const StaticCredentialsProvider(
    AWSCredentials('AKIDEXAMPLE', 'secret'),
  );

  String postResponse;
  String getResponse;
  Exception? postError;
  Exception? deleteError;

  new({this.postResponse = '{}', this.getResponse = '{}', this.postError, this.deleteError});

  final posts = <({Uri uri, Map<String, String>? headers, Map<String, dynamic>? body})>[];
  final gets = <Uri>[];
  final deletes = <Uri>[];

  @override
  Future<String> post({required Uri uri, Map<String, String>? headers, Map<String, dynamic>? body}) async {
    posts.add((uri: uri, headers: headers, body: body));
    if (postError case final error?) throw error;
    return postResponse;
  }

  @override
  Future<String> get({required Uri uri, Map<String, String>? headers}) async {
    gets.add(uri);
    return getResponse;
  }

  @override
  Future<String> delete({required Uri uri, Map<String, String>? headers}) async {
    deletes.add(uri);
    if (deleteError case final error?) throw error;
    return '{}';
  }
}

/// Builds the exception [Signer] throws for a non-2xx AWS response.
AWSHttpException _awsError(int statusCode) {
  final request = AWSHttpRequest(method: AWSHttpMethod.post, uri: Uri.https('scheduler.us-east-1.amazonaws.com', '/'));
  return AWSHttpException(request, 'AWS API Error: $statusCode\nBody: {}');
}

void main() {
  group('createSchedule', () {
    test('posts the schedule definition and returns the schedule ARN', () async {
      const arn = 'arn:aws:scheduler:us-east-1:123456789012:schedule/group/nightly';
      final scheduler = _RecordingScheduler(postResponse: '{"ScheduleArn":"$arn"}');

      final result = await scheduler.createSchedule(
        name: 'nightly',
        groupName: 'group',
        scheduleExpression: 'at(2026-08-07T00:00:00)',
        targetArn: _targetArn,
        targetRoleArn: _roleArn,
      );

      expect(result, arn);
      final call = scheduler.posts.single;
      expect(call.uri, Uri.https('scheduler.us-east-1.amazonaws.com', '/schedules/nightly'));
      expect(call.headers, {AWSHeaders.contentType: 'application/json'});
      expect(call.body, {
        'ClientToken': 'nightly',
        'GroupName': 'group',
        'ScheduleExpression': 'at(2026-08-07T00:00:00)',
        'ScheduleExpressionTimezone': 'UTC',
        'FlexibleTimeWindow': {'Mode': 'OFF'},
        'ActionAfterCompletion': 'DELETE',
        'Target': {
          'Arn': _targetArn,
          'RoleArn': _roleArn,
        },
      });
    });

    test('includes Input and overrides for timezone and action when given', () async {
      final scheduler = _RecordingScheduler(postResponse: '{"ScheduleArn":"arn"}');

      await scheduler.createSchedule(
        name: 'nightly',
        groupName: 'group',
        scheduleExpression: 'cron(0 3 * * ? *)',
        targetArn: _targetArn,
        targetRoleArn: _roleArn,
        input: '{"jobId":42}',
        actionAfterCompletion: 'NONE',
        timezone: 'Europe/London',
      );

      final body = scheduler.posts.single.body!;
      expect(body['ScheduleExpressionTimezone'], 'Europe/London');
      expect(body['ActionAfterCompletion'], 'NONE');
      expect(body['Target'], {
        'Arn': _targetArn,
        'RoleArn': _roleArn,
        'Input': '{"jobId":42}',
      });
    });

    test('returns null when the schedule already exists (409)', () async {
      final scheduler = _RecordingScheduler(postError: _awsError(409));

      final result = await scheduler.createSchedule(
        name: 'nightly',
        groupName: 'group',
        scheduleExpression: 'at(2026-08-07T00:00:00)',
        targetArn: _targetArn,
        targetRoleArn: _roleArn,
      );

      expect(result, isNull);
    });

    test('rethrows other AWS errors', () async {
      final scheduler = _RecordingScheduler(postError: _awsError(500));

      expect(
        () => scheduler.createSchedule(
          name: 'nightly',
          groupName: 'group',
          scheduleExpression: 'at(2026-08-07T00:00:00)',
          targetArn: _targetArn,
          targetRoleArn: _roleArn,
        ),
        throwsA(isA<AWSHttpException>()),
      );
    });

    test('returns null when the response has no ScheduleArn', () async {
      final scheduler = _RecordingScheduler(postResponse: '{}');

      final result = await scheduler.createSchedule(
        name: 'nightly',
        groupName: 'group',
        scheduleExpression: 'at(2026-08-07T00:00:00)',
        targetArn: _targetArn,
        targetRoleArn: _roleArn,
      );

      expect(result, isNull);
    });
  });

  group('getSchedule', () {
    test('requests the schedule by name with the group as a query parameter', () async {
      final scheduler = _RecordingScheduler(getResponse: '{"Name":"nightly","State":"ENABLED"}');

      final result = await scheduler.getSchedule(name: 'nightly', groupName: 'group');

      expect(
        scheduler.gets.single,
        Uri.https('scheduler.us-east-1.amazonaws.com', '/schedules/nightly', {'groupName': 'group'}),
      );
      expect(result, {'Name': 'nightly', 'State': 'ENABLED'});
    });
  });

  group('deleteSchedule', () {
    test('deletes by name with group and client token query parameters', () async {
      final scheduler = _RecordingScheduler();

      await scheduler.deleteSchedule(name: 'nightly', groupName: 'group');

      expect(
        scheduler.deletes.single,
        Uri.https('scheduler.us-east-1.amazonaws.com', '/schedules/nightly', {
          'groupName': 'group',
          'clientToken': 'nightly',
        }),
      );
    });

    test('swallows a 404 by default', () async {
      final scheduler = _RecordingScheduler(deleteError: _awsError(404));
      await scheduler.deleteSchedule(name: 'nightly', groupName: 'group');
    });

    test('rethrows a 404 when throwIfMissing is true', () async {
      final scheduler = _RecordingScheduler(deleteError: _awsError(404));
      expect(
        () => scheduler.deleteSchedule(name: 'nightly', groupName: 'group', throwIfMissing: true),
        throwsA(isA<AWSHttpException>()),
      );
    });

    test('rethrows other AWS errors', () async {
      final scheduler = _RecordingScheduler(deleteError: _awsError(500));
      expect(
        () => scheduler.deleteSchedule(name: 'nightly', groupName: 'group'),
        throwsA(isA<AWSHttpException>()),
      );
    });
  });
}
