import 'package:heart/core/response.dart';
import 'package:heart/globals/config.dart';
import 'package:heart/globals/logging.dart';
import 'package:heart/middleware/authentication.dart';
import 'package:heart/middleware/authenticator.dart';
import 'package:heart/middleware/config.dart';
import 'package:heart/models/errors.dart';
import 'package:heart/routes/charts.dart' as charts;
import 'package:logging/logging.dart';
import 'package:relic/io_adapter.dart';
import 'package:relic/relic.dart';

final _logger = Logger('API');

final _routes = <(String, Method), ModelHandler>{
  ('/charts', .get): charts.getChartPreferences,
  ('/charts', .post): charts.saveChartPreference,
  ('/charts/:preferenceId', .delete): charts.deleteChartPreference,
};

Future<void> main() async {
  final config = AppConfig.fromEnv();
  initLogging(config.logLevel, config.env);

  final app = RelicApp()
    ..use('/', logRequests())
    ..use('/', configuration(override: config))
    ..use('/', authenticator())
    ..use('/', authentication())
    ..fallback = respondWith((_) => JsonResponse.notFound());

  for (final MapEntry(key: (route, verb), value: handler) in _routes.entries) {
    app.add(verb, route, _handler(handler));
  }

  await app.serve();
}

Handler _handler(final ModelHandler handler) {
  return (final Request request) async {
    try {
      final response = await handler(request);
      return JsonResponse.ok(body: response);
    } on ApiException catch (e) {
      _logger.warning('API exception:', e);
      return JsonResponse(e.statusCode, body: e);
    } catch (e, stackTrace) {
      _logger.severe('API server error:', e, stackTrace);
      return JsonResponse.serverError();
    }
  };
}
