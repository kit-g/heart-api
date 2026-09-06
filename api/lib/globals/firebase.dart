import 'package:heart_models/heart_models.dart';
import 'package:logging/logging.dart';
import 'package:openid_client/openid_client.dart';
import 'package:relic/relic.dart' hide Logger;

final _logger = Logger('Firebase');

Issuer? _cachedIssuer;

Future<Issuer> _issuer(String projectId) async {
  return _cachedIssuer ??= await Issuer.discover(Issuer.firebase(projectId));
}

class AuthenticationError implements Exception;

/// A valid, correctly-signed Firebase token whose `firebase.sign_in_provider`
/// is `anonymous`. Distinct from [AuthenticationError] (an invalid token) so
/// the middleware can map the two to different responses.
class AnonymousAccountError implements Exception;

typedef Authenticator = Future<User> Function(String firebaseId, String authToken);

/// True only when the token carries an explicit `firebase.sign_in_provider:
/// anonymous` claim. A token with no `firebase` claim at all is not
/// anonymous — it just didn't come from Firebase's own client SDKs.
bool isAnonymousAccount(OpenIdClaims claims) {
  return switch (claims['firebase']) {
    {'sign_in_provider': 'anonymous'} => true,
    _ => false,
  };
}

Future<User> authenticate(String firebaseId, String authToken) async {
  final client = Client(await _issuer(firebaseId), firebaseId);
  final cred = client.createCredential(idToken: authToken);
  final validations = await cred.validateToken().toList();
  if (validations.isNotEmpty) throw AuthenticationError();
  final claims = cred.idToken.claims;
  if (claims['firebase'] == null) {
    _logger.warning('ID token for ${claims.subject} has no firebase claim');
  } else if (isAnonymousAccount(claims)) {
    throw AnonymousAccountError();
  }
  return claims.toUser();
}

extension on OpenIdClaims {
  User toUser() {
    return User(
      id: subject,
      email: email,
    );
  }
}

final _property = ContextProperty<Authenticator>('Authenticator');

extension RequestConfig on Request {
  Authenticator get authenticator => _property.get(this);

  set authenticator(Authenticator v) => _property[this] = v;
}
