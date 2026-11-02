import 'package:logging/logging.dart';
import 'package:relic/relic.dart' hide Logger;

final _logger = Logger('Request');

/// One log line per request: elapsed time, method, outcome, path.
///
/// Replaces relic's `logRequests()`, which is hardwired to two `print`s per
/// request — an `INFO - <timestamp>` header plus the message — and bakes a
/// second timestamp into the message itself. [initLogging] already stamps every
/// record with a time, so all of that is duplicated bytes in CloudWatch.
Middleware requestLogging() {
  return (Handler next) {
    return (request) async {
      final watch = Stopwatch()..start();

      try {
        final result = await next(request);
        final outcome = switch (result) {
          Response(:final statusCode) => '$statusCode',
          Hijack _ => 'hijacked',
          WebSocketUpgrade _ => 'connected',
        };
        _logger.info(_message(request, watch.elapsed, outcome));
        return result;
      } catch (e, st) {
        _logger.severe(_message(request, watch.elapsed, 'ERROR'), e, st);
        rethrow;
      }
    };
  };
}

String _message(Request request, Duration elapsed, String outcome) {
  final url = request.url;
  final query = url.query.isEmpty ? '' : '?${url.query}';
  final ms = (elapsed.inMicroseconds / 1000).toStringAsFixed(1);

  return '${ms}ms ${request.method.value} [$outcome] ${redactedPath(url.path)}$query';
}

final _invitationLink = RegExp(r'^(/?invitation-links/)[^/]+');

/// [path] as a log can hold it. An invitation's token is a bearer secret in the
/// address, and the database keeps only its hash, so a log must not keep it either.
String redactedPath(String path) => path.replaceFirstMapped(_invitationLink, (match) => '${match[1]}<token>');
