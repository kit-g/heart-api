import 'package:heart/globals/firebase.dart' as firebase;
import 'package:relic/relic.dart';

Middleware authenticator({firebase.Authenticator? implementation}) {
  return (Handler next) {
    return (request) {
      request.authenticator = implementation ?? firebase.authenticate;
      return next(request);
    };
  };
}
