import 'package:heart/core/response.dart';
import 'package:heart/models/errors.dart';
import 'package:logging/logging.dart';
import 'package:relic/relic.dart' hide Logger;

final _logger = Logger('API');

/// Wraps a [ModelHandler] into a Relic [Handler]: serializes the returned model
/// as `200 JSON`, and maps thrown control-flow/errors to status codes —
/// `NoContent` → 204, any [ApiException] → its status, sloppy client input
/// (`TypeError`/`FormatException`) → 400, `UnimplementedError` → 501, and
/// anything else → 500. This is the single choke point every route flows
/// through, so its contract is worth testing directly.
Handler apiHandler(final ModelHandler handler) {
  return (final Request request) async {
    try {
      final response = await handler(request);
      return JsonResponse.ok(body: response);
    } on NoContent {
      return JsonResponse.noContent();
    } on ApiException catch (e) {
      _logger.warning('API exception:', e);
      return JsonResponse(e.statusCode, body: e);
    } on TypeError catch (e) {
      _logger.warning('Malformed request (TypeError):', e);
      return JsonResponse(400, body: BadRequest(reason: 'malformed request: ${e.toString()}'));
    } on FormatException catch (e) {
      _logger.warning('Malformed request (FormatException):', e);
      return JsonResponse(400, body: BadRequest(reason: 'malformed request: ${e.message}'));
    } on UnimplementedError catch (e) {
      _logger.warning('API exception:', e.message);
      return JsonResponse.notImplemented(body: NotImplemented(reason: e.message ?? 'Not implemented'));
    } catch (e, stackTrace) {
      _logger.severe('API server error:', e, stackTrace);
      return JsonResponse.serverError();
    }
  };
}
