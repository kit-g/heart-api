/// Writes everything `tokens.json` generates (`make design`). Run from the
/// package root.
library;

import 'dart:io';

import 'generator.dart';

void main() {
  for (final MapEntry(key: path, value: contents) in outputs(File('tokens.json').readAsStringSync()).entries) {
    File(path).writeAsStringSync(contents);
    stdout.writeln('wrote $path');
  }
}
