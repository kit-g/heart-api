import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:heart_models/heart_models.dart';

/// A personal access token's secret: a fixed prefix (greppable, and eligible
/// for secret scanning) and 32 random bytes, base64url without padding.
abstract final class TokenSecret {
  /// Personal access tokens.
  static const prefix = 'hrt_';

  /// OAuth access tokens: short-lived, recognisable as such when one leaks.
  static const accessPrefix = 'hrt_at_';

  /// OAuth refresh tokens, which are never bearer credentials.
  static const refreshPrefix = 'hrt_rt_';

  static final _random = Random.secure();

  static final _bearer = RegExp(r'^hrt_(at_)?[A-Za-z0-9_-]{43}$');

  static String mint({String prefix = prefix}) => '$prefix${random()}';

  /// 32 random bytes, base64url without padding: 43 characters.
  static String random() {
    final bytes = Uint8List.fromList(List.generate(32, (_) => _random.nextInt(256)));
    return base64Url.encode(bytes).replaceAll('=', '');
  }

  /// What the database stores and looks a token up by. The secret carries 256
  /// bits of entropy, so a plain digest is enough.
  static Uint8List hash(String secret) => Uint8List.fromList(sha256.convert(utf8.encode(secret)).bytes);

  static String hint(String secret) => secret.substring(secret.length - 4);

  /// Whether [value] could be a bearer token at all — personal or OAuth
  /// access — before any lookup.
  static bool looksValid(String value) => _bearer.hasMatch(value);
}

/// One authenticated use of a token: who it acts as, and the account's usage
/// in both rate-limit windows after counting this request.
typedef TokenUse = ({
  String userId,

  /// The resource an OAuth access token is bound to; null for a personal
  /// token, which acts as its owner on every surface.
  String? resource,

  /// The OAuth client a token was issued to; null for a personal token.
  String? clientId,
  List<String> scopes,
  ApiTokenPurpose? purpose,
  DateTime minuteStart,
  int minuteCount,
  DateTime dayStart,
  int dayCount,
});

/// Requests one account may make on the token-authenticated surface.
///
/// The free numbers are a promise: once shipped they may go up, never down.
class ApiLimits {
  final int perMinute;
  final int perDay;

  const new({required this.perMinute, required this.perDay});

  static const free = ApiLimits(perMinute: 20, perDay: 200);
}

abstract interface class ApiTokenService {
  /// Stores a new token for [userId], or returns null when the account
  /// already holds [ApiToken.maxActive] active ones.
  Future<ApiToken?> createToken({
    required String userId,
    required String name,
    ApiTokenPurpose? purpose,
    DateTime? expiresAt,
    required Uint8List tokenHash,
    required String hint,
  });

  /// Every token the account has minted, revoked and expired included,
  /// newest first.
  Future<Iterable<ApiToken>> listTokens(String userId);

  /// Revokes one of [userId]'s tokens. False when there is no such token, or
  /// it is not theirs. Revoking twice keeps the first revocation time.
  Future<bool> revokeToken({required String userId, required String tokenId});

  /// Claims [userId]'s export allowance: one full export a day. Null when
  /// claimed; otherwise when the last export started, which is what the wait
  /// counts from.
  Future<DateTime?> claimExport(String userId);

  /// Resolves a token by its hash for the surface [resource] and, when
  /// [count] is set, counts the request against its account, in one round
  /// trip. Null when the token is unknown, revoked or expired, belongs to a
  /// revoked grant, or is an OAuth token issued for another resource — and
  /// then nothing is counted.
  Future<TokenUse?> useToken(Uint8List tokenHash, {bool count = true, String? resource});
}

abstract interface class ApiTokensResponse implements Model {
  Iterable<ApiToken> get tokens;

  factory({required Iterable<ApiToken> tokens}) = _ApiTokensResponse.new;
}

class _ApiTokensResponse implements ApiTokensResponse {
  @override
  final Iterable<ApiToken> tokens;

  new({required this.tokens});

  @override
  Map<String, dynamic> toMap() {
    return {
      'tokens': tokens.map((each) => each.toMap()).toList(),
    };
  }
}
