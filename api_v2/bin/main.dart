import 'package:aws_client/dynamo_document.dart';
import 'package:heart/core/response.dart';
import 'package:heart/db/db.dart';
import 'package:heart/globals/config.dart';
import 'package:heart/globals/logging.dart';
import 'package:heart/middleware/authentication.dart';
import 'package:heart/middleware/authenticator.dart';
import 'package:heart/middleware/config.dart';
import 'package:heart/middleware/database.dart';
import 'package:heart/models/errors.dart';
import 'package:heart/routes/index.dart';
import 'package:heart_models/heart_models.dart';
import 'package:logging/logging.dart';
import 'package:relic/io_adapter.dart';
import 'package:relic/relic.dart';

final _logger = Logger('API');

final config = AppConfig.fromEnv();

final awsAuth = switch (config.awsProfile) {
  String profile => AwsClientCredentials.fromProfileFile(profile: profile),
  null => AwsClientCredentials.resolve(),
};

final dynamo = DocumentClient(region: config.awsRegion, credentials: awsAuth);
final database = Database(client: dynamo, table: config.workoutsTable);

Handler _handler(final ModelHandler handler) {
  return (final Request request) async {
    try {
      final response = await handler(request);
      return JsonResponse.ok(body: response);
    } on NoContent {
      return JsonResponse.noContent();
    } on ApiException catch (e) {
      _logger.warning('API exception:', e);
      return JsonResponse(e.statusCode, body: e);
    } catch (e, stackTrace) {
      _logger.severe('API server error:', e, stackTrace);
      return JsonResponse.serverError();
    }
  };
}

Future<void> main() async {
  initLogging(config.logLevel, config.env);

  final testAuth = switch (config.testUserId) {
    String id => (String _, String _) async => User(id: id),
    null => null,
  };

  final app = RelicApp()
    ..use('/', logRequests())
    ..use('/', configuration(override: config))
    ..use('/', authenticator(implementation: testAuth))
    ..use('/', authentication())
    ..use('/charts', chartsDb(db: database))
    ..fallback = respondWith((_) => JsonResponse.notFound());

  for (final MapEntry(key: (route, verb), value: handler) in routes.entries) {
    app.add(verb, route, _handler(handler));
  }

  await app.serve();
}
