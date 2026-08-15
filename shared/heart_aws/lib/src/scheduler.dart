part of '../heart_aws.dart';

abstract class SchedulerApi with Signer {
  new();

  @override
  AWSService get service => .scheduler;

  String get _api => 'scheduler.$region.amazonaws.com';

  /// Creates a one-time or recurring schedule.
  /// Returns the schedule ARN, or null if the schedule already existed (409).
  Future<String?> createSchedule({
    required String name,
    required String groupName,
    required String scheduleExpression,
    required String targetArn,
    required String targetRoleArn,
    String? input,
    String actionAfterCompletion = 'DELETE',
    String timezone = 'UTC',
  }) async {
    final uri = Uri.https(_api, '/schedules/$name');

    try {
      final response = await post(
        uri: uri,
        headers: {AWSHeaders.contentType: 'application/json'},
        body: {
          'ClientToken': name,
          'GroupName': groupName,
          'ScheduleExpression': scheduleExpression,
          'ScheduleExpressionTimezone': timezone,
          'FlexibleTimeWindow': {'Mode': 'OFF'},
          'ActionAfterCompletion': actionAfterCompletion,
          'Target': {
            'Arn': targetArn,
            'RoleArn': targetRoleArn,
            'Input': ?input,
          },
        },
      );
      return (jsonDecode(response) as Map<String, dynamic>)['ScheduleArn'] as String?;
    } on AWSHttpException catch (e) {
      if (e.underlyingException?.toString().contains('409') == true) return null;
      rethrow;
    }
  }

  Future<Map<String, dynamic>> getSchedule({required String name, required String groupName}) async {
    final uri = Uri.https(
      _api,
      '/schedules/$name',
      {'groupName': groupName},
    );
    final response = await get(uri: uri);
    return jsonDecode(response) as Map<String, dynamic>;
  }

  Future<void> deleteSchedule({required String name, required String groupName, bool throwIfMissing = false}) async {
    final uri = Uri.https(_api, '/schedules/$name', {
      'groupName': groupName,
      'clientToken': name,
    });
    try {
      await delete(uri: uri);
    } on AWSHttpException catch (e) {
      if (!throwIfMissing && e.underlyingException?.toString().contains('404') == true) return;
      rethrow;
    }
  }

  /// Produces an `at(YYYY-MM-DDTHH:MM:SS)` expression for a one-time schedule.
  static String atExpression(DateTime dt) {
    final u = dt.toUtc();
    return 'at(${u.year.pad(4)}-${u.month.pad()}-${u.day.pad()}T${u.hour.pad()}:${u.minute.pad()}:${u.second.pad()})';
  }
}

class Scheduler extends SchedulerApi {
  @override
  final AWSCredentialsProvider credentialsProvider;

  @override
  final String region;

  new({
    required this.credentialsProvider,
    required this.region,
  });
}
