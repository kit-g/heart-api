import 'package:heart/core/response.dart';
import 'package:heart/models/errors.dart';
import 'package:heart_models/heart_models.dart';
import 'package:logging/logging.dart';
import 'package:relic/relic.dart' hide Logger;

final _logger = Logger('API');

/// Marks a model as freshly inserted rather than an existing row a create
/// resolved to (heart-api#66 — the upsync replay's idempotent creates).
/// `apiHandler` responds `201` for one of these and `200` for a bare [Model],
/// including the "already there" outcome of the very same route. The wire
/// body is identical either way — `toMap()` forwards to [value] — so this is
/// purely a status-code signal, never a shape a client parses.
class Created<T extends Model> implements Model {
  final T value;

  const new(this.value);

  @override
  Map<String, dynamic> toMap() => value.toMap();
}

/// Wraps a [ModelHandler] into a Relic [Handler]: serializes the returned model
/// as `200 JSON` (or `201` when it's a [Created]), and maps thrown
/// control-flow/errors to status codes — `NoContent` → 204, any [ApiException]
/// → its status, sloppy client input (`TypeError`/`FormatException`) → 400,
/// `UnimplementedError` → 501, and anything else → 500. This is the single
/// choke point every route flows through, so its contract is worth testing
/// directly.
Handler apiHandler(ModelHandler handler) {
  return (Request request) async {
    try {
      final response = await handler(request);
      return switch (response) {
        Created() => JsonResponse(201, body: response),
        _ => JsonResponse.ok(body: response),
      };
    } on NoContent {
      return JsonResponse.noContent();
    } on ApiException catch (e) {
      _logger.warning('API exception:', e);
      return JsonResponse(e.statusCode, body: e);
    } on TypeError catch (e) {
      _logger.warning('Malformed request (TypeError):', e);
      return JsonResponse(
        400,
        body: BadRequest(code: 'malformed_request', reason: 'malformed request: ${e.toString()}'),
      );
    } on FormatException catch (e) {
      _logger.warning('Malformed request (FormatException):', e);
      return JsonResponse(
        400,
        body: BadRequest(code: 'malformed_request', reason: 'malformed request: ${e.message}'),
      );
    } on UnimplementedError catch (e) {
      _logger.warning('API exception:', e.message);
      return JsonResponse.notImplemented(body: NotImplemented(reason: e.message ?? 'Not implemented'));
    } catch (e, stackTrace) {
      _logger.severe('API server error:', e, stackTrace);
      return JsonResponse.serverError();
    }
  };
}
