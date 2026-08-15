import 'package:heart_aws/heart_aws.dart';
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
}
