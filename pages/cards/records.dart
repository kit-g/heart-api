/// The `ui://heart/records` view's script: compiled to JS by `make cards`
/// and inlined into the page the API serves (`api/lib/mcp/widgets/records.dart`).
library;

import 'package:heart_pages/cards/bridge.dart';
import 'package:heart_pages/cards/records_card.dart';
import 'package:jaspr/client.dart';

void main() {
  runApp(const McpAppsBridge(RecordsCard.new), attachTo: '#root');
}
