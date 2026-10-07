import 'package:heart/core/routing.dart';
import 'package:heart/db/db.dart';
import 'package:heart/middleware/authentication.dart';
import 'package:heart/middleware/database.dart';
import 'package:heart/middleware/oauth.dart';
import 'package:heart/oauth/fetch.dart';
import 'package:heart/routes/oauth.dart' as oauth;
import 'package:relic/relic.dart';

/// Where the API attaches the authorization server.
const oauthPrefix = '/oauth';

/// The consent page's calls: a signed-in account answering a request, so
/// Firebase-authenticated like the app's own routes, but from a browser,
/// which carries no app version.
final RouteTable _consentRoutes = {
  ('/requests/:requestId', .get): oauth.getConsentRequest,
  ('/requests/:requestId/approve', .post): oauth.approveConsentRequest,
  ('/requests/:requestId/deny', .post): oauth.denyConsentRequest,
};

/// The OAuth 2.1 authorization server as a router of its own. The protocol
/// endpoints authenticate clients themselves (PKCE, `private_key_jwt`) and
/// answer in the protocol's shapes; the consent routes authenticate the
/// account with Firebase.
RelicRouter buildOAuthRouter({required Database database, required JsonFetch fetch}) {
  return RelicRouter()
    ..use('/', oauthDb(db: database))
    ..use('/', jsonFetch(fetch: fetch))
    ..use('/requests', authentication())
    ..add(.get, '/authorize', oauth.authorize)
    ..add(.post, '/token', oauth.token)
    ..add(.post, '/register', oauth.register)
    ..add(.post, '/revoke', oauth.revoke)
    ..addRoutes(_consentRoutes);
}
