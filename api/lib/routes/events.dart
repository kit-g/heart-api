import 'dart:convert';

import 'package:heart/events/account_deletion.dart';
import 'package:heart/events/comment_notification.dart';
import 'package:heart/events/exercise_asset.dart';
import 'package:heart/events/uploads.dart';
import 'package:heart/globals/config.dart';
import 'package:heart/middleware/aws.dart';
import 'package:heart_aws/heart_aws.dart';
import 'package:logging/logging.dart' as logging;
import 'package:relic/relic.dart';

import '../core/request.dart';
import '../models/errors.dart';

final _logger = logging.Logger('events');

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

  /// Runs one record, deciding what its failure means for the SQS message.
  ///
  /// A 4xx `ApiException` is permanent — a malformed event, a row whose foreign
  /// key will never resolve, an id that does not exist. Retrying cannot change
  /// the outcome, so the message is allowed to go, with the DLQ write as the
  /// record of it. Anything else (a pool timeout, an S3 5xx) is transient and
  /// rethrown, which fails the invocation so SQS redelivers.
  ///
  /// Caveat worth knowing: rethrowing fails the *batch*, and the mapping reads
  /// up to 10 records at a time, so records already handled in the same batch
  /// are redelivered too. In practice these events arrive one at a time, and
  /// every handler is idempotent or writes behind a unique key. Moving to
  /// `ReportBatchItemFailures` is the real fix if batches ever fill up.
  Future<void> runRecord(Future<void> Function() handle) async {
    try {
      await handle();
    } on ApiException catch (e, st) {
      // A 5xx ApiException is as transient as an uncaught one; only the 4xx
      // family is the caller's mistake and therefore permanent.
      if (e.statusCode < 400 || e.statusCode >= 500) rethrow;
      _logger.warning('permanent failure on an event record; not retrying', e, st);
      try {
        await onError(e, st);
      } catch (dlqFailure, dlqSt) {
        // The DLQ being unreachable is its own incident, and redelivering a
        // record that can never succeed would not fix it. Keep the decision
        // ("permanent, stop") and leave the louder trace in the log.
        _logger.severe('could not write the DLQ record for $e', dlqFailure, dlqSt);
      }
    }
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
                await runRecord(() => imageUpload(request, bucket, key, onError: onError));
              // use case: account deletion Scheduler callback
              case {
                'Event': 'AccountDeletion',
                'Payload': {'user_id': String userId},
              }:
                await runRecord(() => accountDeletion(request, userId));
              // use case: a new comment was created — render & enqueue push
              case {'type': 'comment.created'}:
                await runRecord(() => commentNotification(request, event));
              // use case: the assets pipeline finished processing an exercise
              // upload — persist its link + dimensions onto the exercise row
              case {'type': 'exercise.asset.processed'}:
                await runRecord(() => exerciseAssetProcessed(request, event));
            }
        }
      }
    default:
      throw ArgumentError({'error': 'unexpected event', 'event': payload});
  }

  // A 204 tells the Lambda Web Adapter the SQS message was processed, and the
  // mapping deletes it.
  //
  // The converse is *not* true, which is the trap this endpoint sat in for a
  // while: a non-2xx is still a normal Lambda result, so the adapter reports
  // success, `Errors` stays at zero and the message is deleted just the same —
  // a permanent failure left no retry, no DLQ entry and nothing to alert on.
  // Only an exception escaping this handler fails the invocation. That is why
  // `runRecord` above rethrows what is worth retrying and DLQs what is not,
  // rather than leaning on the status code to carry that meaning.
  throw const NoContent();
}
