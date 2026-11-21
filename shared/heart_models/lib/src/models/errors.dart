class AccountDeleted implements Exception;

class UpgradeRequired implements Exception;

/// The server answered a request with a named refusal: a 4xx whose body says
/// which one in its `code`.
///
/// It carries the refusal; it doesn't judge it. Some codes are outcomes a caller
/// expects and handles, others mean the client itself is wrong, so a caller
/// catches the codes it handles and lets the rest through to be reported.
/// A status outside 4xx, or an answer without a `code`, is not a refusal.
///
/// [toString] names the status, the code, the method and the route, never the
/// body, which can echo what the caller sent: whatever records the error's text
/// records only those.
class ServerRefusal implements Exception {
  /// The HTTP status, a 4xx.
  final int status;

  /// Which refusal it is. A code this build doesn't know arrives as sent.
  final String code;

  /// The request's HTTP method: `GET`, `PUT`, `DELETE`, …
  final String method;

  /// The route as the caller names it, ids templated: `/v1/goals/{id}`. Never a
  /// path with real ids in it, which would reach crash reports through
  /// [toString] and split one refusal into one group per id.
  final String route;

  /// The rest of the body, `code` aside. [tryParse] makes its top level
  /// unmodifiable.
  final Map<String, dynamic> details;

  const new({
    required this.status,
    required this.code,
    required this.method,
    required this.route,
    this.details = const {},
  }) : assert(status >= 400 && status < 500, 'a refusal is a 4xx');

  /// The refusal in an answer to [method] [route], or null when the answer
  /// isn't one: a status outside 4xx, or a [body] that isn't a JSON object
  /// with a string `code`.
  static ServerRefusal? tryParse({
    required int status,
    required String method,
    required String route,
    required Object? body,
  }) {
    return switch ((status, body)) {
      (>= 400 && < 500, final Map map && {'code': final String code}) => ServerRefusal(
        status: status,
        code: code,
        method: method,
        route: route,
        details: Map.unmodifiable({
          for (final MapEntry(:key, :value) in map.entries)
            if (key case final String key when key != 'code') key: value,
        }),
      ),
      _ => null,
    };
  }

  @override
  String toString() => 'ServerRefusal: $status $code at $method $route';
}
