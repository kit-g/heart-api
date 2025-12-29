import 'package:heart/models/user.dart';
import 'package:openid_client/openid_client.dart';
import 'package:relic/relic.dart';

Issuer? _cachedIssuer;

Future<Issuer> _issuer(String projectId) async {
  return _cachedIssuer ??= await Issuer.discover(Issuer.firebase(projectId));
}

class AuthenticationError implements Exception {}

typedef Authenticator = Future<User> Function(String firebaseId, String authToken);

Future<User> authenticate(String firebaseId, String authToken) async {
  final client = Client(await _issuer(firebaseId), firebaseId);
  final cred = client.createCredential(idToken: authToken);
  final validations = await cred.validateToken().toList();
  if (validations.isNotEmpty) throw AuthenticationError();
  final claims = cred.idToken.claims;
  return claims.toUser();
}

extension on OpenIdClaims {
  User toUser() {
    return User(
      id: subject,
      email: email,
      emailVerified: emailVerified,
    );
  }
}

final _property = ContextProperty<Authenticator>('Authenticator');

extension RequestConfig on Request {
  Authenticator get authenticator => _property.get(this);

  set authenticator(Authenticator v) => _property[this] = v;
}
