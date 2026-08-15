import 'package:heart/core/handler.dart';
import 'package:heart/core/response.dart';
import 'package:heart/db/db.dart';
import 'package:heart/globals/config.dart';
import 'package:heart/globals/firebase.dart' as firebase;
import 'package:heart/middleware/authentication.dart';
import 'package:heart/middleware/authenticator.dart';
import 'package:heart/middleware/aws.dart';
import 'package:heart/middleware/config.dart';
import 'package:heart/middleware/database.dart';
import 'package:heart/middleware/events.dart';
import 'package:heart/middleware/logging.dart';
import 'package:heart/middleware/s3.dart';
import 'package:heart/middleware/version.dart';
import 'package:heart/routes/index.dart';
import 'package:heart/storage/s3.dart';
import 'package:relic/relic.dart' hide Logger;

/// Assembles the fully-wired Relic application — every middleware, the service
/// bindings, and the route table — from its injected dependencies, but does
/// *not* bind a socket. `bin/main.dart` constructs the real dependencies (a
/// Postgres-backed [Database], an S3 [Storage], an SQS publisher) and calls
/// `serve()` on the result; tests construct fakes and drive HTTP through the
/// same wiring, so route registration, middleware order, request parsing, and
/// response serialization are all exercised exactly as they run in production.
///
/// [Database] implements every db-backed service interface, so the single
/// [database] fans out to all the `*Db` middlewares — the same object main used
/// to pass around. Pass [auth] to override token verification (a test hook that
/// returns a fixed user); when null the real Firebase verifier is used.
RelicApp buildApp({
  required AppConfig config,
  required AwsConfig aws,
  required Database database,
  required Storage storage,
  required EventPublisher eventPublisher,
  firebase.Authenticator? auth,
}) {
  bool shouldCheckVersion(Request request) {
    if (config.shouldCheckVersion) return isPublicRoute(request);
    return false;
  }

  final app = RelicApp()
    ..use('/', requestLogging())
    ..use('/', version(minimal: config.minimalAppVersion, shouldCheckVersion: shouldCheckVersion))
    ..use('/', configuration(override: config))
    ..use('/', authenticator(implementation: auth))
    ..use('/', authentication(shouldAuthenticate: isPublicRoute))
    ..use('/', awsConfig(config: aws))
    ..use('/accounts', profilesDb(db: database))
    ..use('/accounts', workoutsDb(db: database))
    ..use('/accounts', goalsDb(db: database))
    ..use('/accounts', connectionsDb(db: database))
    ..use('/accounts', templatesDb(db: database))
    ..use('/accounts', templateFoldersDb(db: database))
    ..use('/accounts', imageStorageDb(db: storage))
    ..use('/charts', chartsDb(db: database))
    ..use('/exercise-preferences', exercisePreferencesDb(db: database))
    ..use('/connections', connectionsDb(db: database))
    ..use('/comments', commentsDb(db: database))
    ..use('/comments', connectionsDb(db: database))
    ..use('/comments', events(publisher: eventPublisher))
    ..use('/devices', devicesDb(db: database))
    ..use('/exercises', exercisesDb(db: database))
    ..use('/goals', goalsDb(db: database))
    ..use('/feedback', imageStorageDb(db: storage))
    ..use('/workouts', workoutsDb(db: database))
    ..use('/workouts', imageDb(db: database))
    ..use('/workouts', imageStorageDb(db: storage))
    ..use('/templates', templatesDb(db: database))
    ..use('/template-folders', templateFoldersDb(db: database))
    ..use('/events', imageStorageDb(db: storage))
    ..use('/events', imageDb(db: database))
    ..use('/events', profilesDb(db: database))
    ..use('/events', devicesDb(db: database))
    ..use('/events', exercisesDb(db: database))
    ..use('/events', events(publisher: eventPublisher))
    ..fallback = respondWith((_) => JsonResponse.notFound());

  for (final MapEntry(key: (route, verb), value: handler) in routes.entries) {
    app.add(verb, route, apiHandler(handler));
  }

  return app;
}
