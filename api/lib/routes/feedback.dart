import 'dart:convert';

import 'package:heart/core/request.dart';
import 'package:heart/globals/config.dart';
import 'package:heart/globals/globals.dart';
import 'package:heart/middleware/aws.dart';
import 'package:heart/middleware/s3.dart';
import 'package:heart/models/errors.dart';
import 'package:heart_aws/heart_aws.dart';
import 'package:heart_models/heart_models.dart';
import 'package:mime/mime.dart';
import 'package:relic/relic.dart';

class FeedbackResponse implements Model {
  final String url;
  final Map<String, String> fields;

  const FeedbackResponse({required this.url, required this.fields});

  @override
  Map<String, dynamic> toMap() {
    return {
      'url': url,
      'fields': fields,
    };
  }
}

Future<Model> submitFeedback(final Request request) async {
  final body = await request.json();
  final message = body['message'] as String?;

  if (message == null || message.isEmpty) {
    throw const BadRequest(reason: 'message is required');
  }

  final config = request.config;
  final userId = request.userId;

  switch (body) {
    case {'mimeType': String mimeType} when config.allowedMimeTypes.contains(mimeType):
      final ext = extensionFromMime(mimeType) ?? 'jpg';
      final timestamp = DateTime.now().toIso8601String();
      final screenshotKey = 'feedback/$userId/$timestamp.$ext';

      final presignedUrl = await request.imageStorageService.presignUpload(
        key: screenshotKey,
        mimeType: mimeType,
      );

      final screenshotResponse = FeedbackResponse(
        url: presignedUrl.url,
        fields: presignedUrl.fields,
      );

      final sns = Sns(
        credentialsProvider: request.awsConfig.credentialsProvider,
        region: request.awsConfig.region,
      );

      await sns.publish(
        topicArn: config.monitoringTopicArn,
        message: jsonEncode({
          'user_id': userId,
          'message': message,
          'screenshot_key': screenshotKey,
        }),
        subject: 'User Feedback',
      );
      return screenshotResponse;
    default:
      throw const NoContent();
  }
}
