import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:heart_models/heart_models.dart';

/// A personal access token's secret: a fixed prefix (greppable, and eligible
/// for secret scanning) and 32 random bytes, base64url without padding.
abstract final class TokenSecret {
  static const prefix = 'hrt_';

  static final _random = Random.secure();

  static String mint() {
    final bytes = Uint8List.fromList(List.generate(32, (_) => _random.nextInt(256)));
    return '$prefix${base64Url.encode(bytes).replaceAll('=', '')}';
  }

  /// What the database stores and looks a token up by. The secret carries 256
  /// bits of entropy, so a plain digest is enough.
  static Uint8List hash(String secret) => Uint8List.fromList(sha256.convert(utf8.encode(secret)).bytes);

  static String hint(String secret) => secret.substring(secret.length - 4);

  /// Whether [value] could be a token at all, before any lookup.
  static bool looksValid(String value) => value.startsWith(prefix) && value.length == prefix.length + 43;
}

/// One authenticated use of a token: who it acts as, and the account's usage
/// in both rate-limit windows after counting this request.
typedef TokenUse = ({
  String userId,
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

  /// Resolves a token by its hash and counts the request against its account,
  /// in one round trip. Null when the token is unknown, revoked or expired.
  Future<TokenUse?> useToken(Uint8List tokenHash);
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
