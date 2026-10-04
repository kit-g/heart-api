import 'package:heart/core/handler.dart';
import 'package:heart/core/response.dart';
import 'package:relic/relic.dart';

/// Path and verb to handler: one per surface, so each surface is its own
/// router with its own middleware.
typedef RouteTable = Map<(String, Method), ModelHandler>;

/// Registers [table] on [router], each handler wrapped by [apiHandler].
///
/// Relic settles a method miss from the router's own lookup, before any
/// handler exists — so the 405 it writes never enters the chain: no CORS
/// headers on it, no log line for it, and a body unlike every other refusal
/// here. Registering the verbs a path does not serve keeps each one inside
/// the chain, and is also what lets a preflight reach `cors` at all, OPTIONS
/// being one of them.
void addRoutes(Router<Handler> router, RouteTable table) {
  for (final MapEntry(key: (route, verb), value: handler) in table.entries) {
    router.add(verb, route, apiHandler(handler));
  }

  final verbsByPath = <String, Set<Method>>{};
  for (final (path, verb) in table.keys) {
    (verbsByPath[path] ??= <Method>{}).add(verb);
  }

  for (final MapEntry(key: path, value: verbs) in verbsByPath.entries) {
    for (final verb in _browserVerbs.difference(verbs)) {
      router.add(verb, path, respondWith((_) => JsonResponse.methodNotAllowed(allowed: verbs)));
    }
  }
}

/// The verbs a browser can be made to send, and so the ones whose 405 a browser
/// could ever have to read. `connect` and `trace` are forbidden method names it
/// will never issue, and keep relic's own answer.
const _browserVerbs = <Method>{.get, .head, .post, .put, .patch, .delete, .options};
