/// Writes a page per MCP Apps widget that plays the host: it frames the
/// widget in a sandboxed iframe, answers `ui/initialize`, and posts a sample
/// tool result, so a widget can be looked at in a browser without a deploy.
///
///   dart run tool/widget_harness.dart [out-dir]   (default: ../build/widgets)
///
/// Open `<out-dir>/<widget>.html`; `?theme=dark` or `?theme=light` sets the
/// host's theme, and no parameter leaves it to the OS. `?units=imperial`
/// sends the result as an imperial user's, and `?width=760` frames the card
/// as wide as a desktop host's column (420 by default). `?height=900`
/// holds the frame at that height instead of the size the card reports,
/// for a headless screenshot, which may not deliver the later reports.
library;

import 'dart:convert';
import 'dart:io';

import 'package:heart/mcp/widgets.dart';

void main(List<String> arguments) {
  final out = Directory(arguments.firstOrNull ?? '../build/widgets')..createSync(recursive: true);
  for (final widget in widgets) {
    final file = File('${out.path}/${widget.name}.html')..writeAsStringSync(_page(widget, _samples[widget.name]!));
    stdout.writeln(file.absolute.path);
  }
}

String _page(McpWidget widget, Map<String, dynamic> structured) {
  final result = {
    'content': [
      {'type': 'text', 'text': jsonEncode(structured)},
    ],
    'structuredContent': structured,
    'isError': false,
  };
  return '''
<!DOCTYPE html><html><head><meta charset="utf-8"><title>${widget.title} harness</title>
<style>body { margin: 24px; font: 13px system-ui; background: #ddd; } iframe { width: 420px; border: 0; display: block; }</style>
</head><body>
<p>${widget.uri}</p>
<iframe id="view" sandbox="allow-scripts" srcdoc="${const HtmlEscape(HtmlEscapeMode.attribute).convert(widget.html)}"></iframe>
<script>
var frame = document.getElementById('view');
var params = new URLSearchParams(location.search);
var theme = params.get('theme');
var result = ${jsonEncode(result)};
if (params.get('units')) result.structuredContent.unitSystem = params.get('units');
if (params.get('width')) frame.style.width = params.get('width') + 'px';
var fixedHeight = params.get('height');
if (fixedHeight) frame.style.height = fixedHeight + 'px';
function post(m) { frame.contentWindow.postMessage(m, '*'); }
window.addEventListener('message', function (event) {
  if (event.source !== frame.contentWindow) return;
  var m = event.data;
  if (m.method === 'ui/initialize') {
    post({ jsonrpc: '2.0', id: m.id, result: {
      protocolVersion: '2026-01-26', hostInfo: { name: 'harness', version: '1' }, hostCapabilities: {},
      hostContext: { theme: theme || undefined, locale: 'en-GB', timeZone: 'Europe/London', displayMode: 'inline' }
    } });
  } else if (m.method === 'ui/notifications/initialized') {
    post({ jsonrpc: '2.0', method: 'ui/notifications/tool-input', params: { arguments: {} } });
    post({ jsonrpc: '2.0', method: 'ui/notifications/tool-result', params: result });
  } else if (m.method === 'ui/notifications/size-changed') {
    if (!fixedHeight) frame.style.height = m.params.height + 'px';
  }
});
</script></body></html>
''';
}

/// Results shaped as the tools return them (`api/lib/mcp/tools.dart`).
const _samples = <String, Map<String, dynamic>>{
  'workout': {
    'id': '019a0000-0000-7000-8000-0000000000aa',
    'name': 'Pull Day',
    'start': '2026-08-21T17:02:00.000Z',
    'end': '2026-08-21T18:26:00.000Z',
    'caloriesEstimate': 412,
    'exercises': [
      {
        'id': '01900000-0000-7000-8000-000000000001',
        'name': 'Deadlift',
        'category': 'Barbell',
        'sets': [
          {'type': 'warmup', 'weightKg': 100, 'reps': 5},
          {'weightKg': 225, 'reps': 5, 'rpe': 8},
          {'weightKg': 225, 'reps': 5, 'rpe': 9},
          {'type': 'failure', 'weightKg': 225, 'reps': 3},
        ],
      },
      {
        'id': '01900000-0000-7000-8000-000000000004',
        'name': 'Chest Press (Machine)',
        'category': 'Machine',
        'sets': [
          {'weightKg': 58.967, 'reps': 14},
          {'weightKg': 58.967, 'reps': 14},
          {'weightKg': 58.967, 'reps': 14},
        ],
      },
      {
        'id': '01900000-0000-7000-8000-000000000002',
        'name': 'Pull Up',
        'category': 'Reps Only',
        'note': 'Wide grip',
        'sets': [
          {'reps': 12},
          {'reps': 10},
          {'reps': 8, 'completed': false},
        ],
      },
      {
        'id': '01900000-0000-7000-8000-000000000003',
        'name': 'Rowing Machine',
        'category': 'Cardio',
        'sets': [
          {'distanceKm': 2, 'seconds': 480},
        ],
      },
    ],
  },
  'exercise-progress': {
    'exercise': {'id': '01900000-0000-7000-8000-000000000001', 'name': 'Bench Press', 'category': 'Barbell'},
    'sessions': [
      {
        'workoutId': 'w6',
        'at': '2026-10-14T17:00:00.000Z',
        'sets': [
          {'weightKg': 102.5, 'reps': 5},
        ],
        'metrics': {
          'topSetWeight': 102.5,
          'estimatedOneRepMax': 115.313,
          'totalVolume': 1537.5,
          'averageWorkingWeight': 102.5,
          'totalReps': 15,
          'maxConsecutiveReps': 5,
        },
      },
      {
        'workoutId': 'w5',
        'at': '2026-10-07T17:00:00.000Z',
        'sets': <Object>[],
        'metrics': {
          'topSetWeight': 100,
          'estimatedOneRepMax': 112.5,
          'totalVolume': 1500,
          'averageWorkingWeight': 100,
          'totalReps': 15,
          'maxConsecutiveReps': 5,
        },
      },
      {
        'workoutId': 'w4',
        'at': '2026-09-30T17:00:00.000Z',
        'sets': <Object>[],
        'metrics': {
          'topSetWeight': 100,
          'estimatedOneRepMax': 109.091,
          'totalVolume': 1200,
          'averageWorkingWeight': 100,
          'totalReps': 12,
          'maxConsecutiveReps': 4,
        },
      },
      {
        'workoutId': 'w3',
        'at': '2026-09-23T17:00:00.000Z',
        'sets': <Object>[],
        'metrics': {
          'topSetWeight': 97.5,
          'estimatedOneRepMax': 109.688,
          'totalVolume': 1462.5,
          'averageWorkingWeight': 97.5,
          'totalReps': 15,
          'maxConsecutiveReps': 5,
        },
      },
      {
        'workoutId': 'w2',
        'at': '2026-09-16T17:00:00.000Z',
        'sets': <Object>[],
        'metrics': {
          'topSetWeight': 95,
          'estimatedOneRepMax': 106.875,
          'totalVolume': 1425,
          'averageWorkingWeight': 95,
          'totalReps': 15,
          'maxConsecutiveReps': 5,
        },
      },
      {
        'workoutId': 'w1',
        'at': '2026-09-09T17:00:00.000Z',
        'sets': <Object>[],
        'metrics': {
          'topSetWeight': 92.5,
          'estimatedOneRepMax': 104.063,
          'totalVolume': 1387.5,
          'averageWorkingWeight': 92.5,
          'totalReps': 15,
          'maxConsecutiveReps': 5,
        },
      },
    ],
    'cursor': 'w1',
  },
  'records': {
    'records': [
      {
        'exercise': {'id': 'a', 'name': 'Bench Press', 'category': 'Barbell'},
        'sessions': 24,
        'firstAt': '2026-03-02T17:00:00.000Z',
        'heaviest': {
          'weightKg': 110,
          'reps': 1,
          'workoutId': 'w',
          'at': '2026-10-01T17:00:00.000Z',
          'previous': {'weightKg': 107.5, 'reps': 1, 'workoutId': 'v', 'at': '2026-08-01T17:00:00.000Z'},
        },
        'oneRepMax': {
          'value': 115.313,
          'weightKg': 102.5,
          'reps': 5,
          'workoutId': 'w',
          'at': '2026-10-14T17:00:00.000Z',
        },
        'bestVolume': {'value': 840, 'weightKg': 84, 'reps': 10, 'workoutId': 'w', 'at': '2026-06-11T17:00:00.000Z'},
        'repMaxes': [
          {'reps': 1, 'weightKg': 110, 'workoutId': 'w', 'at': '2026-10-01T17:00:00.000Z'},
          {'reps': 5, 'weightKg': 102.5, 'workoutId': 'w', 'at': '2026-10-14T17:00:00.000Z'},
        ],
        'totalVolume': 31250,
        'lastTrained': '2026-10-14T17:00:00.000Z',
      },
      {
        'exercise': {'id': 'b', 'name': 'Running', 'category': 'Cardio'},
        'sessions': 9,
        'firstAt': '2026-05-02T07:00:00.000Z',
        'longestDistance': {'distanceKm': 12.4, 'seconds': 4020, 'workoutId': 'r', 'at': '2026-09-20T07:00:00.000Z'},
        'bestPace': {
          'pace': 301.2,
          'distanceKm': 5,
          'seconds': 1506,
          'workoutId': 'r',
          'at': '2026-10-04T07:00:00.000Z',
        },
        'totalDistance': 61.8,
        'lastTrained': '2026-10-11T07:00:00.000Z',
      },
    ],
  },
  'template': {
    'status': 'preview',
    'template': {
      'folder': {'id': 'f', 'name': 'Upper/lower'},
      'name': 'Upper A',
      'note': 'Heavy pressing, rows for balance.',
      'exercises': [
        {
          'exerciseId': 'a',
          'name': 'Bench Press',
          'category': 'Barbell',
          'rest': 150,
          'sets': [
            {'type': 'warmup', 'weightKg': 40, 'reps': 10},
            {
              'weightKg': 80,
              'reps': 6,
              'target': {
                'reps': {'min': 6, 'max': 8},
                'rir': 2,
              },
            },
            {
              'weightKg': 80,
              'reps': 6,
              'target': {
                'reps': {'min': 6},
              },
            },
          ],
        },
        {
          'exerciseId': 'b',
          'name': 'Bent Over Row',
          'category': 'Barbell',
          'superset': 1,
          'sets': [
            {
              'target': {
                'reps': {'min': 8, 'max': 12},
              },
            },
          ],
        },
        {
          'exerciseId': 'c',
          'name': 'Plank',
          'category': 'Duration',
          'superset': 1,
          'sets': [
            {
              'seconds': 45,
              'target': {
                'seconds': {'min': 45, 'max': 45},
              },
            },
          ],
        },
      ],
    },
  },
};
