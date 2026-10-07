import 'package:heart/oauth/fetch.dart';
import 'package:relic/relic.dart';

final _fetchProperty = ContextProperty<JsonFetch>('JsonFetch');

/// How the OAuth endpoints fetch client metadata documents and key sets:
/// [guardedJsonFetch] in production, a fake in tests.
Middleware jsonFetch({required JsonFetch fetch}) {
  return (Handler next) {
    return (request) {
      _fetchProperty[request] = fetch;
      return next(request);
    };
  };
}

extension OAuthFetch on Request {
  JsonFetch get jsonFetch => _fetchProperty.get(this);

  set jsonFetch(JsonFetch v) => _fetchProperty[this] = v;
}
