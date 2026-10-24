/// The `ui://heart/exercise-progress` view's script: compiled to JS by `make cards`
/// and inlined into the page the API serves (`api/lib/mcp/widgets/progress.dart`).
library;

import 'package:heart_pages/cards/bridge.dart';
import 'package:heart_pages/cards/progress_card.dart';
import 'package:jaspr/client.dart';

void main() {
  runApp(const McpAppsBridge(ProgressCard.new), attachTo: '#root');
}
