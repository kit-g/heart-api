import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:heart/core/response.dart';
import 'package:heart/globals/config.dart';
import 'package:heart/globals/globals.dart';
import 'package:heart/middleware/database.dart';
import 'package:heart/models/errors.dart';
import 'package:heart/models/tokens.dart';
import 'package:heart_models/heart_models.dart';
import 'package:logging/logging.dart';
import 'package:relic/relic.dart' hide Logger;

final _logger = Logger('TokenAuthentication');
final _usage = Logger('ApiUsage');

/// Authenticates the `/me` surface with a personal access token instead of a
/// Firebase ID token, counts the request against the account's rate limits,
/// and logs one usage line per request.
Middleware tokenAuthentication({DateTime Function()? clock}) {
  return (Handler next) {
    return (request) async {
      switch (await checkToken(request, clock: clock)) {
        case TokenRefused(:final response):
          logApiUsage(request, surface: 'me', status: response.statusCode);
          return response;
        case TokenAccepted(:final use):
          request.user = User(id: use.userId);
          final result = await next(request);
          logApiUsage(
            request,
            surface: 'me',
            status: switch (result) {
              Response(:final statusCode) => statusCode,
              _ => null,
            },
            use: use,
          );
          return result;
      }
    };
  };
}

sealed class TokenCheck;

final class TokenAccepted implements TokenCheck {
  final TokenUse use;

  const new(this.use);
}

final class TokenRefused implements TokenCheck {
  final Response response;

  const new(this.response);
}

/// Resolves the request's bearer token and, when [count] is set, counts the
/// request and enforces the account's limits. A request that doesn't count
/// is never refused for being over a limit.
///
/// Unknown, revoked, expired and malformed tokens all get the same
/// `401 invalid_token`: a caller can't act on the difference, and telling them
/// apart would reveal which tokens once existed.
Future<TokenCheck> checkToken(Request request, {bool count = true, DateTime Function()? clock}) async {
  final secret = switch (request.headers.authorization) {
    BearerAuthorizationHeader(:final token) when TokenSecret.looksValid(token) => token,
    _ => null,
  };

  final TokenUse? use;
  try {
    use = switch (secret) {
      final String secret => await request.apiTokenService.useToken(TokenSecret.hash(secret), count: count),
      null => null,
    };
  } catch (e, st) {
    _logger.severe('Token lookup failed', e, st);
    return TokenRefused(JsonResponse.serverError());
  }

  if (use == null) {
    return TokenRefused(
      JsonResponse(
        401,
        body: const Unauthorized(code: 'invalid_token', reason: 'missing, unknown, revoked or expired token'),
        headers: .build(
          (headers) => headers.wwwAuthenticate = .new(
            scheme: 'Bearer',
            parameters: [const .new('realm', 'heart')],
          ),
        ),
      ),
    );
  }
  if (!count) return TokenAccepted(use);

  final limits = request.config.freeApiLimits;
  final at = (clock ?? () => DateTime.now().toUtc())();
  final (String, DateTime)? exceeded = switch (use) {
    _ when use.minuteCount > limits.perMinute => (
      '${limits.perMinute} requests a minute',
      use.minuteStart.add(const Duration(minutes: 1)),
    ),
    _ when use.dayCount > limits.perDay => (
      '${limits.perDay} requests a day',
      use.dayStart.add(const Duration(days: 1)),
    ),
    _ => null,
  };

  if (exceeded case (final limit, final resetsAt)) {
    final retryAfter = resetsAt.difference(at).inSeconds.clamp(1, 86400);
    return TokenRefused(
      JsonResponse(
        429,
        body: TooManyRequests(reason: 'rate limit of $limit reached', retryAfter: retryAfter),
        headers: .build((headers) => headers.retryAfter = .new(delay: retryAfter)),
      ),
    );
  }
  return TokenAccepted(use);
}

/// One structured line per request, for learning who uses the API and how
/// much of it is AI. Never bodies, query values or anything from a workout.
void logApiUsage(
  Request request, {
  required String surface,
  int? status,
  TokenUse? use,
  String? route,
  String? client,
}) {
  _usage.info(
    jsonEncode({
      'surface': surface,
      'route': route ?? request.url.path,
      'status': status,
      'credential': 'pat',
      'client': client,
      'purpose': use?.purpose?.name,
      'uaFamily': _userAgentFamily(request.headers.userAgent),
      'account': switch (use) {
        final TokenUse use => _pseudonym(use.userId),
        null => null,
      },
    }),
  );
}

/// Enough of an account id to count distinct callers without logging the id.
String _pseudonym(String userId) => sha256.convert(utf8.encode(userId)).toString().substring(0, 16);

/// The tool behind a User-Agent, reduced to a family so logs group by what
/// called rather than by version string. Unrecognised agents keep their
/// product token, which is what a tool setting a descriptive agent sends.
String? _userAgentFamily(String? userAgent) {
  final ua = userAgent?.trim().toLowerCase();
  if (ua == null || ua.isEmpty) return null;
  for (final (needle, family) in _families) {
    if (ua.contains(needle)) return family;
  }
  return ua.split(RegExp(r'[\s/;(]')).first;
}

const _families = [
  ('claude-code', 'claude-code'),
  ('claude', 'claude'),
  ('chatgpt', 'chatgpt'),
  ('openai', 'openai'),
  ('cursor', 'cursor'),
  ('home assistant', 'home-assistant'),
  ('homeassistant', 'home-assistant'),
  ('google-apps-script', 'google-apps-script'),
  ('python-requests', 'python-requests'),
  ('python-httpx', 'python-httpx'),
  ('aiohttp', 'aiohttp'),
  ('python-urllib', 'python-urllib'),
  ('curl/', 'curl'),
  ('wget/', 'wget'),
  ('node-fetch', 'node'),
  ('undici', 'node'),
  ('axios', 'node'),
  ('node', 'node'),
  ('go-http-client', 'go'),
  ('dart:io', 'dart'),
  ('dart/', 'dart'),
  ('postman', 'postman'),
  ('insomnia', 'insomnia'),
  ('mozilla/', 'browser'),
];
