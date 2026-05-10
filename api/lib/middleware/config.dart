import 'package:heart/globals/config.dart';
import 'package:relic/relic.dart';

Middleware configuration({AppConfig? override}) {
  return (final Handler next) {
    return (final request) {
      request.config = override ?? AppConfig.fromEnv();
      return next(request);
    };
  };
}
