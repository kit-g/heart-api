import 'package:heart/core/handler.dart';
import 'package:heart/core/response.dart';
import 'package:heart/db/db.dart';
import 'package:heart/globals/config.dart';
import 'package:heart/globals/logging.dart';
import 'package:heart/middleware/authentication.dart';
import 'package:heart/middleware/authenticator.dart';
import 'package:heart/middleware/aws.dart';
import 'package:heart/middleware/config.dart';
import 'package:heart/middleware/database.dart';
import 'package:heart/middleware/events.dart';
import 'package:heart/middleware/s3.dart';
import 'package:heart/middleware/version.dart';
import 'package:heart/routes/index.dart';
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

bool _shouldCheckVersion(final Request request) {
  if (_config.shouldCheckVersion) return isPublicRoute(request);
  return false;
}

Future<void> main() async {
  hierarchicalLoggingEnabled = true;
  AWSLogger().logLevel = LogLevel.error;
  initLogging(_config.logLevel, _config.env);

  final testAuth = switch (_config.testUserId) {
    String id => (String _, String _) async => User(id: id),
    null => null,
  };

  final app = RelicApp()
    ..use('/', logRequests())
    ..use('/', version(minimal: _config.minimalAppVersion, shouldCheckVersion: _shouldCheckVersion))
    ..use('/', configuration(override: _config))
    ..use('/', authenticator(implementation: testAuth))
    ..use('/', authentication(shouldAuthenticate: isPublicRoute))
    ..use('/', awsConfig(config: _awsConfig))
    ..use('/accounts', profilesDb(db: _database))
    ..use('/accounts', workoutsDb(db: _database))
    ..use('/accounts', connectionsDb(db: _database))
    ..use('/accounts', templatesDb(db: _database))
    ..use('/accounts', imageStorageDb(db: _storage))
    ..use('/charts', chartsDb(db: _database))
    ..use('/exercise-preferences', exercisePreferencesDb(db: _database))
    ..use('/connections', connectionsDb(db: _database))
    ..use('/comments', commentsDb(db: _database))
    ..use('/comments', connectionsDb(db: _database))
    ..use('/comments', events(publisher: _events))
    ..use('/devices', devicesDb(db: _database))
    ..use('/exercises', exercisesDb(db: _database))
    ..use('/goals', goalsDb(db: _database))
    ..use('/feedback', imageStorageDb(db: _storage))
    ..use('/workouts', workoutsDb(db: _database))
    ..use('/workouts', imageDb(db: _database))
    ..use('/workouts', imageStorageDb(db: _storage))
    ..use('/templates', templatesDb(db: _database))
    ..use('/events', imageStorageDb(db: _storage))
    ..use('/events', imageDb(db: _database))
    ..use('/events', profilesDb(db: _database))
    ..use('/events', devicesDb(db: _database))
    ..use('/events', exercisesDb(db: _database))
    ..use('/events', events(publisher: _events))
    ..fallback = respondWith((_) => JsonResponse.notFound());

  for (final MapEntry(key: (route, verb), value: handler) in routes.entries) {
    app.add(verb, route, apiHandler(handler));
  }

  await app.serve();
}
