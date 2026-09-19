library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:asn1lib/asn1lib.dart';
import 'package:logging/logging.dart';
import 'package:pointycastle/export.dart';

import '../globals/config.dart';
import '../models/apple.dart';

part 'key.dart';

final _logger = Logger('AppleIdentity');

/// Apple's identity service: the `aud` of every client secret, and the host
/// both calls go to.
const _appleId = 'https://appleid.apple.com';

/// One form POST to Apple, as `(status, body)`. Injected so everything around
/// it — the client lookup, the secret, the response shapes, the failure
/// handling — is testable without a network.
typedef AppleTransport = Future<(int status, String body)> Function(Uri uri, Map<String, String> form);

/// Talks to Apple on a deleting account's behalf.
///
/// Nothing here throws. The contract in [AppleIdentityService] is that a
/// deletion proceeds whatever Apple says, so every failure is logged at
/// `SEVERE` — which is what the monitoring stack alarms on — and swallowed.
/// Being told about it is the whole remedy: an account whose grant was not
/// revoked is already deleted, and no retry can reach it.
class AppleIdentity implements AppleIdentityService {
  final AppleConfig _config;
  final AppleTransport _post;

  late final _key = AppleSignInKey.parse(
    pem: _config.privateKey,
    teamId: _config.teamId,
    keyId: _config.keyId,
  );

  new({required this._config, AppleTransport? transport}) : _post = transport ?? _httpPost;

  @override
  Future<String?> exchangeAuthorizationCode({required String code, required String clientId}) async {
    return _call(
      path: 'token',
      clientId: clientId,
      what: 'exchange an authorization code',
      form: {
        'code': code,
        'grant_type': 'authorization_code',
        'redirect_uri': ?_config.clients[clientId],
      },
      onSuccess: (body) => switch (body) {
        {'refresh_token': String token} => token,
        // A 200 without one is Apple changing its mind about the response
        // shape, not a user-visible failure — but it leaves nothing to revoke.
        _ => _failed('exchange an authorization code', 200, body),
      },
    );
  }

  @override
  Future<void> revokeGrant({required String refreshToken, required String clientId}) async {
    await _call(
      path: 'revoke',
      clientId: clientId,
      what: 'revoke a grant',
      form: {
        'token': refreshToken,
        'token_type_hint': 'refresh_token',
      },
      // Apple answers a revoke with 200 and an empty body, and says nothing
      // different about a token that was already revoked or has expired.
      onSuccess: (_) => null,
    );
  }

  /// The shape both calls share: look the client up, sign a secret for it,
  /// post, and turn anything other than a 200 into a logged null.
  Future<String?> _call({
    required String path,
    required String clientId,
    required String what,
    required Map<String, String> form,
    required String? Function(Map<String, dynamic> body) onSuccess,
  }) async {
    if (!_config.clients.containsKey(clientId)) {
      _logger.severe(
        'cannot $what: no Sign in with Apple client is configured for "$clientId". '
        'The account still deletes, but its Apple grant survives it.',
      );
      return null;
    }

    try {
      final (status, body) = await _post(
        Uri.parse('$_appleId/auth/$path'),
        {
          'client_id': clientId,
          'client_secret': _key.clientSecretFor(clientId),
          ...form,
        },
      );

      final decoded = switch (body.isEmpty) {
        true => const <String, dynamic>{},
        false => switch (jsonDecode(body)) {
          final Map<String, dynamic> json => json,
          _ => const <String, dynamic>{},
        },
      };

      return switch (status) {
        200 => onSuccess(decoded),
        _ => _failed(what, status, decoded),
      };
    } catch (e, st) {
      // Network, TLS, a malformed body, a key that will not parse. None of it
      // is the deleting user's problem.
      _logger.severe('failed to $what against Apple', e, st);
      return null;
    }
  }

  /// Logs Apple's refusal and returns null.
  ///
  /// Only Apple's own `error` field is quoted. The rest of the exchange — the
  /// authorization code, the refresh token, the signed secret — never reaches
  /// a log line, here or anywhere else.
  String? _failed(String what, int status, Map<String, dynamic> body) {
    _logger.severe(
      'Apple refused to $what: HTTP $status${switch (body['error']) {
        final String error => ', $error',
        _ => '',
      }}. The account still deletes, but its Apple grant survives it.',
    );
    return null;
  }
}

/// The default transport: a plain form POST, no AWS signing, no auth header —
/// the client secret in the body is the whole credential.
Future<(int, String)> _httpPost(Uri uri, Map<String, String> form) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
  try {
    final request = await client.postUrl(uri);
    final body = utf8.encode(
      form.entries.map((e) => '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}').join('&'),
    );
    request.headers
      ..contentType = ContentType('application', 'x-www-form-urlencoded', charset: 'utf-8')
      ..contentLength = body.length;
    request.add(body);

    final response = await request.close();
    return (response.statusCode, await response.transform(utf8.decoder).join());
  } finally {
    client.close(force: true);
  }
}

/// What an environment without Sign in with Apple secrets runs instead.
///
/// The deletion path is then identical minus the revocation — no null checks,
/// no branch — and each skipped call says so once, loudly enough that an
/// environment missing its secrets is noticed rather than assumed to be quiet.
class UnconfiguredAppleIdentity implements AppleIdentityService {
  const new();

  @override
  Future<String?> exchangeAuthorizationCode({required String code, required String clientId}) async {
    _logger.severe(_reason('exchange an authorization code', clientId));
    return null;
  }

  @override
  Future<void> revokeGrant({required String refreshToken, required String clientId}) async {
    _logger.severe(_reason('revoke a grant', clientId));
  }

  static String _reason(String what, String clientId) {
    return 'cannot $what for "$clientId": Sign in with Apple is not configured in this environment. '
        'The account still deletes, but its Apple grant survives it.';
  }
}
