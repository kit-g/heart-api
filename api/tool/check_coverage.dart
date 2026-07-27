import 'dart:io';

/// Fails (exit 1) if overall line coverage in an lcov file is below a floor.
///
///   dart run tool/check_coverage.dart [floorPercent] [lcovPath]
///
/// Defaults: floor 60, path coverage/lcov.info. Ratchet the floor up over time.
void main(List<String> args) {
  final floor = double.parse(args.isNotEmpty ? args[0] : '60');
  final path = args.length > 1 ? args[1] : 'coverage/lcov.info';

  final file = File(path);
  if (!file.existsSync()) {
    stderr.writeln('coverage file not found: $path (did the coverage run produce it?)');
    exit(2);
  }

  var found = 0;
  var hit = 0;
  for (final line in file.readAsLinesSync()) {
    if (line.startsWith('LF:')) found += int.parse(line.substring(3));
    if (line.startsWith('LH:')) hit += int.parse(line.substring(3));
  }

  final pct = found == 0 ? 0.0 : hit / found * 100;
  final label = '${pct.toStringAsFixed(1)}% ($hit/$found lines)';

  if (pct + 1e-9 < floor) {
    stderr.writeln('❌ Coverage $label is below the floor of $floor%.');
    exit(1);
  }
  stdout.writeln('✅ Coverage $label meets the floor of $floor%.');
}
