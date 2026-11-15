import 'package:mockito/mockito.dart';

import '../mocks.mocks.dart';

/// A config serving English alone, for a route that names exercises in the
/// request's locale and is tested without the app's middleware.
MockAppConfig englishConfig() {
  final config = MockAppConfig();
  when(config.supportedLocales).thenReturn(['en']);
  when(config.defaultLocale).thenReturn('en');
  return config;
}
