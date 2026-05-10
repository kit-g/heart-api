import 'package:heart/globals/firebase.dart' as firebase;
import 'package:relic/relic.dart';

Middleware authenticator({firebase.Authenticator? implementation}) {
  return (final Handler next) {
    return (final request) {
      request.authenticator = implementation ?? firebase.authenticate;
      return next(request);
    };
  };
}
