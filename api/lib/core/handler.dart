import 'dart:typed_data';

import 'package:heart/core/response.dart';
import 'package:heart/db/db.dart';
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

/// Taken, not done: `apiHandler` responds `202` for one of these. The body is
/// [value]'s, which says what was kept and what happens next.
class Accepted<T extends Model> implements Model {
  final T value;

  const new(this.value);

  @override
  Map<String, dynamic> toMap() => value.toMap();
}

/// A file rather than JSON: `apiHandler` answers `200` with [bytes] as the
/// body, typed [mimeType], offered for download as [filename].
class Download implements Model {
  final List<int> bytes;
  final MimeType mimeType;
  final String filename;

  const new({required this.bytes, required this.mimeType, required this.filename});

  @override
  Map<String, dynamic> toMap() => throw UnsupportedError('a download has no JSON form');
}

/// `303 See Other` to [location]: the result lives elsewhere, such as a file
/// too large to answer inline, behind a short-lived link.
class SeeOther implements Model {
  final Uri location;

  const new(this.location);

  @override
  Map<String, dynamic> toMap() => {'location': location.toString()};
}

/// Wraps a [ModelHandler] into a Relic [Handler]: serializes the returned model
/// as `200 JSON` (`201` for a [Created], `202` for an [Accepted]), and maps thrown
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
        Accepted() => JsonResponse(202, body: response),
        Download(:final bytes, :final mimeType, :final filename) => Response.ok(
          body: Body.fromData(Uint8List.fromList(bytes), mimeType: mimeType),
          headers: Headers.build(
            (headers) =>
                headers.contentDisposition = ContentDispositionHeader.parse('attachment; filename="$filename"'),
          ),
        ),
        SeeOther(:final location) => JsonResponse(
          303,
          body: response,
          headers: Headers.build((headers) => headers.location = location),
        ),
        _ => JsonResponse.ok(body: response),
      };
    } on NoContent {
      return JsonResponse.noContent();
    } on TooManyRequests catch (e) {
      return JsonResponse(
        e.statusCode,
        body: e,
        headers: Headers.build((headers) => headers.retryAfter = RetryAfterHeader(delay: e.retryAfter)),
      );
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
      // A constraint violation that no statement mapped is the caller naming a
      // row that isn't there — a refusal, not a fault. Without this it reaches
      // the 500 below, which the app cannot tell from an outage and so retries
      // or aborts on (heart-api#74). See `apiExceptionForDbError`.
      if (apiExceptionForDbError(e) case final rejected?) {
        _logger.warning('Rejected reference:', e);
        return JsonResponse(rejected.statusCode, body: rejected);
      }
      _logger.severe('API server error:', e, stackTrace);
      return JsonResponse.serverError();
    }
  };
}
