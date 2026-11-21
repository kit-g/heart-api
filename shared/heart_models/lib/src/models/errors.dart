class AccountDeleted implements Exception;

class UpgradeRequired implements Exception;

/// The server answered a request with a named refusal: a 4xx whose body says
/// which one in its `code`.
///
/// A refusal is an answer, not a fault: `name_taken`, `goal_limit`,
/// `stale_cursor` and the rest are outcomes a caller expects and handles.
/// Timeouts, 5xx and answers without a `code` (API Gateway's own throttle among
/// them) are not refusals.
///
/// [toString] names the status, the code and the route, and never the body,
/// which can echo what the caller sent: whatever records the error's text
/// records only those three.
class ServerRefusal implements Exception {
  /// The HTTP status, always a 4xx.
  final int status;

  /// Which refusal it is. A code this build doesn't know arrives as sent.
  final String code;

  /// The route as the caller names it, ids templated: `/v1/goals/{id}`.
  final String route;

  /// The rest of the body, `code` aside: `retryAfter` on `rate_limited`, the
  /// prose `error` and `reason`, and whatever a later server adds.
  final Map<String, dynamic> details;

  const new({required this.status, required this.code, required this.route, this.details = const {}});

  /// The refusal in an answer to [route], or null when the answer isn't one:
  /// a status outside 4xx, or a [body] that isn't a JSON object with a string
  /// `code`.
  static ServerRefusal? tryParse({required int status, required String route, required Object? body}) {
    return switch (body) {
      final Map<String, dynamic> map && {'code': final String code} when status >= 400 && status < 500 => ServerRefusal(
        status: status,
        code: code,
        route: route,
        details: Map.unmodifiable({...map}..remove('code')),
      ),
      _ => null,
    };
  }

  @override
  String toString() => 'ServerRefusal: $status $code at $route';
}
