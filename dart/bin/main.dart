import 'package:heart/core/response.dart';
import 'package:heart/middleware/authentication.dart';
import 'package:heart/middleware/authenticator.dart';
import 'package:heart/middleware/config.dart';
import 'package:heart/models/errors.dart';
import 'package:heart/routes/charts.dart' as charts;
import 'package:relic/io_adapter.dart';
import 'package:relic/relic.dart';

final _routes = <(String, Method), ModelHandler>{

};

Future<void> main() async {
  final app = RelicApp()
    ..use('/', logRequests(logger: (msg, {stackTrace, type = .info}) => print(msg)))
    ..use('/', configuration())
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
      return JsonResponse(e.statusCode, body: e);
    } catch (e) {
      return JsonResponse.serverError();
    }
  };
}
