import 'package:heart/core/app.dart';
import 'package:heart/db/db.dart';
import 'package:heart/globals/config.dart';
import 'package:heart/globals/logging.dart';
import 'package:heart/middleware/aws.dart';
import 'package:heart/middleware/events.dart';
import 'package:heart/storage/s3.dart';
import 'package:heart_aws/heart_aws.dart';
import 'package:heart_models/heart_models.dart';
import 'package:logging/logging.dart';
import 'package:postgres/postgres.dart' hide Connection;
import 'package:relic/relic.dart' hide Logger;

final _config = AppConfig.fromEnv();

final _credentialsProvider = switch (_config.awsProfile) {
  String profile => AWSCredentialsProvider.profile(profile),
  null => const AWSCredentialsProvider.defaultChain(),
};

final _awsConfig = AwsConfig(credentialsProvider: _credentialsProvider, region: _config.awsRegion);

final _pool = Pool.withEndpoints(
  [_config.db.endpoint],
  settings: const PoolSettings(maxConnectionCount: 1, applicationName: 'heart-api'),
);

final _database = Database(pool: _pool);
final _storage = Storage(
  credentialsProvider: _credentialsProvider,
  region: _config.awsRegion,
  contentBucket: _config.contentBucket,
);

final _events = SqsEventPublisher(
  Sqs(credentialsProvider: _credentialsProvider, region: _config.awsRegion),
);

Future<void> main() async {
  hierarchicalLoggingEnabled = true;
  AWSLogger().logLevel = LogLevel.error;
  initLogging(_config.logLevel, _config.env);

  final testAuth = switch (_config.testUserId) {
    String id => (String _, String _) async => User(id: id),
    null => null,
  };

  final app = buildApp(
    config: _config,
    aws: _awsConfig,
    database: _database,
    storage: _storage,
    eventPublisher: _events,
    auth: testAuth,
  );

  await app.serve();
}
