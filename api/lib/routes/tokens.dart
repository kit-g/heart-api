import 'package:heart/core/handler.dart';
import 'package:heart/globals/globals.dart';
import 'package:heart/inputs/inputs.dart';
import 'package:heart/middleware/database.dart';
import 'package:heart/models/errors.dart';
import 'package:heart/models/tokens.dart';
import 'package:heart_models/heart_models.dart';
import 'package:relic/relic.dart';

/// Mints a token. The response is the only time its secret exists in
/// plaintext; the server keeps a digest.
Future<Model> createApiToken(Request req) async {
  final input = await ApiTokenCreateIn.fromRequest(req);
  final secret = TokenSecret.mint();
  final token = await req.apiTokenService.createToken(
    userId: req.userId,
    name: input.name,
    purpose: input.purpose,
    expiresAt: switch (input.expiry) {
      .year => DateTime.now().toUtc().add(const Duration(days: 365)),
      .never => null,
    },
    tokenHash: TokenSecret.hash(secret),
    hint: TokenSecret.hint(secret),
  );
  if (token == null) {
    throw const BadRequest(
      code: 'token_limit',
      reason: 'you can have at most ${ApiToken.maxActive} active tokens; revoke one first',
    );
  }
  return Created(MintedApiToken(token: token, secret: secret));
}

Future<ApiTokensResponse> listApiTokens(Request req) async {
  final tokens = await req.apiTokenService.listTokens(req.userId);
  return ApiTokensResponse(tokens: tokens);
}

Future<Model> revokeApiToken(Request req) => revokeApiTokenById(req, req.rawPathParameters[#tokenId]!);

Future<Model> revokeApiTokenById(Request req, String tokenId) async {
  if (!isUuidV7(tokenId)) throw NotFound(type: 'token', id: tokenId);
  final revoked = await req.apiTokenService.revokeToken(userId: req.userId, tokenId: tokenId);
  if (!revoked) throw NotFound(type: 'token', id: tokenId);
  throw const NoContent();
}
