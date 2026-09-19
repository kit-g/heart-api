/// A revocable Sign in with Apple grant: the long-lived token, and the client
/// it was issued to.
///
/// The two travel together because Apple accepts neither alone — a revoke is
/// rejected unless the client secret is signed for the same client the token
/// belongs to — and storing one without the other is storing nothing.
typedef AppleGrant = ({String refreshToken, String clientId});

/// Apple's half of account deletion: turning the short-lived authorization code
/// the app collects at confirmation into something the deletion schedule can
/// still use days later, and spending it when it fires.
///
/// Every method is best-effort by contract. A deletion that Apple refuses to
/// cooperate with is still a deletion — the account goes either way — so
/// failures are reported as `null`/no-op rather than thrown, and the caller
/// never branches on them.
abstract interface class AppleIdentityService {
  /// Exchanges an authorization code for the long-lived refresh token that
  /// [revokeGrant] will spend.
  ///
  /// [clientId] is the Apple client the code was issued to; the client secret
  /// is signed for that client specifically and Apple rejects a mismatch.
  /// Returns null when the exchange fails for any reason.
  Future<String?> exchangeAuthorizationCode({
    required String code,
    required String clientId,
  });

  /// Revokes [refreshToken], removing the app from the user's Apple ID and
  /// deactivating a Hide My Email relay if they used one.
  ///
  /// Idempotent as far as callers are concerned: an already-revoked or expired
  /// token is indistinguishable from a fresh one here, and neither throws.
  Future<void> revokeGrant({
    required String refreshToken,
    required String clientId,
  });
}
