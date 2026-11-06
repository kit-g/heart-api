import 'package:heart/globals/config.dart';
import 'package:heart_aws/heart_aws.dart';
import 'package:logging/logging.dart' as logging;
import 'package:relic/relic.dart';

class AwsConfig {
  final AWSCredentialsProvider credentialsProvider;
  final String region;

  new({
    required this.credentialsProvider,
    required this.region,
  });
}

final _awsConfigProperty = ContextProperty<AwsConfig>('AwsConfig');

Middleware awsConfig({required AwsConfig config}) {
  return (Handler next) {
    return (request) {
      _awsConfigProperty[request] = config;
      return next(request);
    };
  };
}

extension StorageService on Request {
  AwsConfig get awsConfig => _awsConfigProperty.get(this);

  set awsConfig(AwsConfig v) => _awsConfigProperty[this] = v;

  /// Tells the owner, best-effort: whatever the alert is about has already
  /// happened, and failing to say so must never fail the request.
  Future<void> alertOwner({required String subject, required String message}) async {
    try {
      final sns = Sns(credentialsProvider: awsConfig.credentialsProvider, region: awsConfig.region);
      await sns.publish(topicArn: config.monitoringTopicArn, subject: subject, message: message);
    } catch (e, st) {
      _logger.warning('failed to publish the alert "$subject"', e, st);
    }
  }
}

final _logger = logging.Logger('Alerts');
