import 'package:heart_aws/heart_aws.dart';
import 'package:relic/relic.dart';

/// Publishes JSON-shaped events to an SQS queue. Wraps the raw `Sqs` client so
/// handlers can take a dependency on this interface and tests can mock it.
abstract interface class EventPublisher {
  Future<void> publish({
    required String queueUrl,
    required Map<String, dynamic> message,
  });
}

class SqsEventPublisher implements EventPublisher {
  final Sqs _sqs;

  SqsEventPublisher(this._sqs);

  @override
  Future<void> publish({required String queueUrl, required Map<String, dynamic> message}) async {
    await _sqs.sendJsonMessage(queueUrl: queueUrl, message: message);
  }
}

final _eventPublisherProperty = ContextProperty<EventPublisher>('EventPublisher');

Middleware events({required EventPublisher publisher}) {
  return (final Handler next) {
    return (final request) {
      _eventPublisherProperty[request] = publisher;
      return next(request);
    };
  };
}

extension RequestEventPublisher on Request {
  EventPublisher get events => _eventPublisherProperty.get(this);

  set events(EventPublisher p) => _eventPublisherProperty[this] = p;
}
