import 'dart:convert';
import 'dart:io';

import 'package:logging/logging.dart';

import 'config.dart';

Level _getLevel(String v) {
  return switch (v) {
    'ALL' => Level.ALL,
    _ => Level.OFF,
  };
}

void initLogging(String level, Env env) {
  Logger.root
    ..level = _getLevel(level)
    ..onRecord.listen(
      (record) {
        switch (env) {
          case .dev:
            record.toStdOut();
          case .prod:
            record.structured();
        }
      },
    );
}

extension on LogRecord {
  void toStdOut() {
    final color = switch (level) {
      .SEVERE => '\x1B[31m', // red
      .WARNING => '\x1B[33m', // yellow
      _ => '\x1B[32m', // green
    };
    final reset = '\x1B[0m';

    final buffer = StringBuffer()..write('$color${level.name}$reset: $time: [$loggerName] $message');

    if (error != null) {
      buffer.write('\n\x1B[31mError: $error\x1B[0m');
    }

    if (stackTrace != null) {
      buffer.write('\n$stackTrace');
    }

    stdout.writeln(buffer.toString());
  }

  void structured() {
    final record = {
      'loggerName': loggerName,
      'level': level.name,
      'time': time.toIso8601String(),
      'message': message,
      'error': ?error?.toString(),
      'stackTrace': ?stackTrace?.toString(),
    };

    stdout.writeln(jsonEncode(record));
  }
}
