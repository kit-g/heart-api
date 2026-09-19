import 'package:relic/relic.dart';

import '../models/apple.dart';

final _appleProperty = ContextProperty<AppleIdentityService>('AppleIdentityService');

Middleware appleIdentity({required AppleIdentityService service}) {
  return (Handler next) {
    return (request) {
      _appleProperty[request] = service;
      return next(request);
    };
  };
}

extension RequestAppleIdentity on Request {
  AppleIdentityService get apple => _appleProperty.get(this);

  set apple(AppleIdentityService v) => _appleProperty[this] = v;
}
