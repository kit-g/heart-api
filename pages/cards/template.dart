/// The `ui://heart/template` view's script: compiled to JS by `make cards`
/// and inlined into the page the API serves (`api/lib/mcp/widgets/template.dart`).
library;

import 'package:heart_pages/cards/bridge.dart';
import 'package:heart_pages/cards/template_card.dart';
import 'package:jaspr/client.dart';

void main() {
  runApp(const McpAppsBridge(TemplateCard.new), attachTo: '#root');
}
