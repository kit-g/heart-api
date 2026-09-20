import 'package:relic/relic.dart';

/// The request headers a browser must be told it may send. Anything the client
/// sets that is not CORS-safelisted has to appear here or the browser refuses
/// the request before it leaves the machine — `content-type: application/json`
/// and `authorization` above all, which is every call this API serves.
///
/// `referer` and `user-agent` are deliberately absent: they are forbidden
/// header names, set by the browser itself and rejected if script tries.
const _allowedRequestHeaders = {
  'accept',
  'accept-language',
  'authorization',
  'content-type',
  'x-app-version',
  'x-timezone',
};

/// How long a browser may reuse one preflight. An hour keeps the extra round
/// trip off all but the first call of a session; Chrome caps at two.
const _maxAge = Duration(hours: 1);

final _varyOnOrigin = VaryHeader.headers(fields: const ['origin']);

/// Cross-origin access for browser clients, from an [origins] allowlist.
///
/// Belongs outermost in the chain, above the version gate and authentication.
/// A preflight is an `OPTIONS` carrying neither a bearer token nor an app
/// version, so anything that inspects those would reject it before it could be
/// answered — and an error response that reaches a browser without these
/// headers is read as a network failure rather than the 401 or 426 it is.
///
/// No `Access-Control-Allow-Credentials`: the session travels as a bearer
/// token in a header, never a cookie, so nothing here needs credentialed
/// requests — and allowing them would forbid answering a wildcard origin.
Middleware cors({required Set<String> origins, required Set<Method> methods}) {
  final allowMethods = AccessControlAllowMethodsHeader.methods(methods.toList());
  final allowHeaders = AccessControlAllowHeadersHeader.headers(_allowedRequestHeaders);

  void decorate(MutableHeaders headers, {required String origin, required bool allowed, required bool preflight}) {
    // Stated whether or not the origin passes: the answer genuinely differs
    // per origin, and a cache that does not know it would serve one origin's
    // response to another.
    headers.vary = _varyOnOrigin;
    if (!allowed) return;

    headers.accessControlAllowOrigin = AccessControlAllowOriginHeader.origin(origin: Uri.parse(origin));
    if (!preflight) return;

    headers
      ..accessControlAllowMethods = allowMethods
      ..accessControlAllowHeaders = allowHeaders
      ..accessControlMaxAge = _maxAge.inSeconds;
  }

  return (Handler next) {
    return (request) async {
      final origin = switch (request.headers) {
        {'origin': [final String value, ...]} => value,
        _ => null,
      };

      // Every call the mobile app makes arrives without an Origin. Nothing to
      // negotiate, so nothing is rewritten.
      if (origin == null) return next(request);

      final allowed = origins.contains(origin);

      // The route table carries no OPTIONS, so a preflight allowed through
      // would come back as `route_not_found` — answered here instead. An
      // OPTIONS with no Origin is not a preflight and falls through to that
      // 404, which is the honest answer to it.
      if (request.method == .options) {
        return Response(
          204,
          headers: Headers.build(
            (headers) => decorate(headers, origin: origin, allowed: allowed, preflight: true),
          ),
        );
      }

      final result = await next(request);
      return switch (result) {
        Response response => response.copyWith(
          headers: response.headers.transform(
            (headers) => decorate(headers, origin: origin, allowed: allowed, preflight: false),
          ),
        ),
        _ => result,
      };
    };
  };
}
