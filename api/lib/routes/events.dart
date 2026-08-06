import 'dart:convert';

import 'package:heart/events/account_deletion.dart';
import 'package:heart/events/comment_notification.dart';
import 'package:heart/events/exercise_asset.dart';
import 'package:heart/events/uploads.dart';
import 'package:heart/globals/config.dart';
import 'package:heart/middleware/aws.dart';
import 'package:heart_aws/heart_aws.dart';
import 'package:relic/relic.dart';

import '../core/request.dart';
import '../models/errors.dart';

/// Dedicated handler for non-HTTP events.
/// Listens on /events.
///
/// Since our Dart API is wrapped in lambda_web_adapter
/// https://crates.io/crates/lambda_web_adapter
/// it exposes that endpoint, so we route events from here.
Future<NoContent> handler(Request request) async {
  final requestContext = request.headers['x-amzn-request-context']?.firstOrNull;

  // API Gateway would have that header populated.
  // That would mean it's a network request to /events,
  // which is only allowed in local development
  if (!request.config.allowNonHttpEvents && requestContext != 'null') {
    throw const Forbidden(reason: 'Forbidden');
  }

  final payload = await request.json();
  final sqs = Sqs(
    credentialsProvider: request.awsConfig.credentialsProvider,
    region: request.awsConfig.region,
  );

  // Awaited by the handlers it is passed to: the Lambda runtime may freeze
  // as soon as the response is returned, so an un-awaited DLQ write can be
  // dropped silently.
  Future<String> onError(Object error, [StackTrace? st]) async {
    return sqs.sendJsonMessage(
      queueUrl: request.config.eventsDlq,
      message: {
        'error': error.toString(),
        'stacktrace': st?.toString(),
        'event': payload,
      },
    );
  }

  switch (payload) {
    // SQS
    case {'Records': List records}:
      for (final record in records) {
        switch (record) {
          case {'body': String body}:
            final event = jsonDecode(body);

            switch (event) {
              // use case: user file upload
              // infrastructure is: S3 -> EventBridge -> SQS -> this lambda
              case {
                'detail-type': 'Object Created',
                'detail': {
                  'bucket': {'name': String bucket},
                  'object': {'key': String key},
                },
              }:
                await imageUpload(request, bucket, key, onError: onError);
              // use case: account deletion Scheduler callback
              case {
                'Event': 'AccountDeletion',
                'Payload': {'user_id': String userId},
              }:
                await accountDeletion(request, userId);
              // use case: a new comment was created — render & enqueue push
              case {'type': 'comment.created'}:
                await commentNotification(request, event);
              // use case: the assets pipeline finished processing an exercise
              // upload — persist its link + dimensions onto the exercise row
              case {'type': 'exercise.asset.processed'}:
                await exerciseAssetProcessed(request, event);
            }
        }
      }
    default:
      throw ArgumentError({'error': 'unexpected event', 'event': payload});
  }

  // Returning a 204 tells the Lambda Web Adapter to mark the SQS message as successfully processed
  throw const NoContent();
}
