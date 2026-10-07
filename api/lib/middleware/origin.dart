import 'package:heart/core/response.dart';
import 'package:heart/models/errors.dart';
import 'package:relic/relic.dart';

/// The header CloudFront adds on its way to the MCP host's function URL.
const originSecretHeader = 'x-heart-origin';

/// Refuses a request that didn't come through the MCP host's CloudFront: the
/// function URL is public, so the distribution proves itself with [secret].
/// Compared in constant time, so the refusal says nothing about how close a
/// guess was.
Middleware cloudFrontOnly(String secret) {
  return (Handler next) {
    return (request) {
      final presented = request.headers[originSecretHeader]?.firstOrNull ?? '';
      if (_same(presented, secret)) return next(request);
      return JsonResponse(
        403,
        body: const Forbidden(reason: 'only through mcp.heart-of.me', code: 'origin'),
      );
    };
  };
}

bool _same(String a, String b) {
  if (a.length != b.length) return false;
  var difference = 0;
  for (var i = 0; i < a.length; i++) {
    difference |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
  }
  return difference == 0;
}
