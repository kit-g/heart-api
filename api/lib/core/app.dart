import 'package:heart/core/handler.dart';
import 'package:heart/core/response.dart';
import 'package:heart/db/db.dart';
import 'package:heart/globals/config.dart';
import 'package:heart/globals/firebase.dart' as firebase;
import 'package:heart/middleware/apple.dart';
import 'package:heart/middleware/authentication.dart';
import 'package:heart/middleware/authenticator.dart';
import 'package:heart/middleware/aws.dart';
import 'package:heart/middleware/config.dart';
import 'package:heart/middleware/cors.dart';
import 'package:heart/middleware/database.dart';
import 'package:heart/middleware/events.dart';
import 'package:heart/middleware/logging.dart';
import 'package:heart/middleware/s3.dart';
import 'package:heart/middleware/version.dart';
import 'package:heart/models/apple.dart';
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
  required AppleIdentityService apple,
  firebase.Authenticator? auth,
}) {
  bool shouldCheckVersion(Request request) {
    if (config.shouldCheckVersion) return isPublicRoute(request);
    return false;
  }

  // Outermost but for the log line: a preflight carries no bearer token and no
  // app version, so both gates below would turn one away, and the refusals
  // they issue have to reach a browser wearing CORS headers to be read as
  // refusals at all. Methods come from the route table so the advertised set
  // cannot drift from the one that exists.
  final crossOrigin = cors(
    origins: config.allowedOrigins,
    methods: routes.keys.map((route) => route.$2).toSet(),
  );

  final app = RelicApp()
    ..use('/', requestLogging())
    ..use('/', crossOrigin)
    ..use('/', version(minimal: config.minimalAppVersion, shouldCheckVersion: shouldCheckVersion))
    ..use('/', configuration(override: config))
    ..use('/', authenticator(implementation: auth))
    ..use('/', authentication(shouldAuthenticate: isPublicRoute))
    ..use('/', awsConfig(config: aws))
    ..use('/accounts', profilesDb(db: database))
    ..use('/accounts', appleIdentity(service: apple))
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
    ..use('/events', appleIdentity(service: apple))
    ..use('/events', devicesDb(db: database))
    ..use('/events', exercisesDb(db: database))
    ..use('/events', events(publisher: eventPublisher))
    // The router's own 404, distinguishable from a handler's: a client calling
    // a path or verb this table does not carry gets `route_not_found`, so a
    // wrong endpoint can be told apart from a missing row without guessing.
    //
    // Wrapped by hand because `use` maps stored routes, and the fallback is
    // not one — it is the terminal handler the router falls through to, so
    // nothing registered above reaches it on its own, logging included.
    ..fallback = requestLogging()(crossOrigin(respondWith((_) => JsonResponse.noSuchRoute())));

  for (final MapEntry(key: (route, verb), value: handler) in routes.entries) {
    app.add(verb, route, apiHandler(handler));
  }

  // Relic settles a method miss from the router's own lookup, before any
  // handler exists — so the 405 it writes never enters the chain: no CORS
  // headers on it, no log line for it, and a body unlike every other refusal
  // here. Registering the verbs a path does not serve keeps each one inside
  // the chain, and is also what lets a preflight reach `cors` at all, OPTIONS
  // being one of them.
  final verbsByPath = <String, Set<Method>>{};
  for (final (path, verb) in routes.keys) {
    (verbsByPath[path] ??= <Method>{}).add(verb);
  }

  for (final MapEntry(key: path, value: verbs) in verbsByPath.entries) {
    for (final verb in _browserVerbs.difference(verbs)) {
      app.add(verb, path, respondWith((_) => JsonResponse.methodNotAllowed(allowed: verbs)));
    }
  }

  return app;
}

/// The verbs a browser can be made to send, and so the ones whose 405 a browser
/// could ever have to read. `connect` and `trace` are forbidden method names it
/// will never issue, and keep relic's own answer.
const _browserVerbs = <Method>{.get, .head, .post, .put, .patch, .delete, .options};
