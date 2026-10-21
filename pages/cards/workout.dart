/// The `ui://heart/workout` view's script: compiled to JS by `make cards`
/// and inlined into the page the API serves (`api/lib/mcp/widgets/workout.dart`).
library;

import 'package:heart_pages/cards/bridge.dart';
import 'package:heart_pages/cards/workout_card.dart';
import 'package:jaspr/client.dart';

void main() {
  runApp(const McpAppsBridge(WorkoutCard.new), attachTo: '#root');
}
