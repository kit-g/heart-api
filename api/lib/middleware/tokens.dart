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
///
/// Unknown, revoked, expired and malformed tokens all get the same
/// `401 invalid_token`: a caller can't act on the difference, and telling them
/// apart would reveal which tokens once existed.
Middleware tokenAuthentication({DateTime Function()? clock}) {
  final now = clock ?? () => DateTime.now().toUtc();

  return (Handler next) {
    return (request) async {
      final secret = switch (request.headers.authorization) {
        BearerAuthorizationHeader(:final token) when TokenSecret.looksValid(token) => token,
        _ => null,
      };

      final TokenUse? use;
      try {
        use = secret == null ? null : await request.apiTokenService.useToken(TokenSecret.hash(secret));
      } catch (e, st) {
        _logger.severe('Token lookup failed', e, st);
        return JsonResponse.serverError();
      }

      if (use == null) {
        _log(request, status: 401);
        return JsonResponse(
          401,
          body: const Unauthorized(code: 'invalid_token', reason: 'missing, unknown, revoked or expired token'),
        );
      }

      final limits = request.config.freeApiLimits;
      final at = now();
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
        _log(request, status: 429, use: use);
        return JsonResponse(
          429,
          body: TooManyRequests(reason: 'rate limit of $limit reached', retryAfter: retryAfter),
          headers: Headers.build((headers) => headers.retryAfter = RetryAfterHeader(delay: retryAfter)),
        );
      }

      request.user = User(id: use.userId);
      final result = await next(request);
      _log(request, status: result is Response ? result.statusCode : null, use: use);
      return result;
    };
  };
}

/// One structured line per request, for learning who uses the API and how
/// much of it is AI. Never bodies, query values or anything from a workout.
void _log(Request request, {int? status, TokenUse? use}) {
  _usage.info(
    jsonEncode({
      'surface': 'me',
      'route': request.url.path,
      'status': status,
      'credential': 'pat',
      'client': null,
      'purpose': use?.purpose?.name,
      'uaFamily': userAgentFamily(request.headers.userAgent),
      'account': use == null ? null : pseudonym(use.userId),
    }),
  );
}

/// Enough of an account id to count distinct callers without logging the id.
String pseudonym(String userId) => sha256.convert(utf8.encode(userId)).toString().substring(0, 16);

/// The tool behind a User-Agent, reduced to a family so logs group by what
/// called rather than by version string. Unrecognised agents keep their
/// product token, which is what a tool setting a descriptive agent sends.
String? userAgentFamily(String? userAgent) {
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
