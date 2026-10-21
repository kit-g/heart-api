import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:jaspr/client.dart';
import 'package:jaspr/dom.dart';
import 'package:web/web.dart' as web;

import 'format.dart';

/// Draws a card from a tool result.
typedef CardBuilder = Component Function(Map<String, Object?> structuredContent, Format format);

/// The view's side of the MCP Apps bridge (ext-apps 2026-01-26), with no SDK:
/// `ui/initialize`, then `ui/notifications/initialized`; the host answers
/// with its context and later sends the tool result, which [card] draws. Size
/// changes go back up so the host can fit the frame. ChatGPT's older
/// `window.openai.toolOutput` is read too. A port of the hand-written
/// `_bridgeJs` the first cards shipped with (heart-api#183).
///
/// Browser only: it is what an MCP Apps page runs, never part of a
/// server-rendered page.
class McpAppsBridge extends StatefulComponent {
  const new(this.card, {super.key});

  final CardBuilder card;

  @override
  State<McpAppsBridge> createState() => _McpAppsBridgeState();
}

class _McpAppsBridgeState extends State<McpAppsBridge> {
  Map<String, Object?>? _result;
  var _format = IntlFormat();
  var _lastWidth = 0, _lastHeight = 0;

  static const _initializeId = 1;

  @override
  void initState() {
    super.initState();
    web.window.addEventListener('message', _onMessage.toJS);
    _post({
      'jsonrpc': '2.0',
      'id': _initializeId,
      'method': 'ui/initialize',
      'params': {
        'appInfo': {'name': 'heart', 'version': '1.0.0'},
        'appCapabilities': {
          'availableDisplayModes': ['inline'],
        },
        'protocolVersion': '2026-01-26',
      },
    });

    if (globalContext['openai'] case final JSObject openai) {
      _context({'theme': _read(openai['theme']), 'locale': _read(openai['locale'])});
      if (_read(openai['toolOutput']) case final Map<String, Object?> output) {
        _show({'structuredContent': output});
      }
      web.window.addEventListener(
        'openai:set_globals',
        (web.CustomEvent event) {
          if (_read(event.detail) case {'globals': final Map<String, Object?> globals}) {
            if (globals['theme'] != null || globals['locale'] != null) {
              _context({'theme': globals['theme'], 'locale': globals['locale']});
            }
            if (globals['toolOutput'] case final Map<String, Object?> output) _show({'structuredContent': output});
          }
        }.toJS,
      );
    }
  }

  // Compared with strictEquals, not ==: a Dart == on the cross-origin parent
  // reads a property off it under dart2js -O3 and up, which the sandbox
  // answers with a SecurityError, and the card never initializes.
  void _onMessage(web.MessageEvent event) {
    if (!event.source.strictEquals(web.window.parent).toDart) return;
    switch (_read(event.data)) {
      case {'jsonrpc': '2.0', 'id': _initializeId, 'result': final Map<String, Object?> result}:
        _context(result['hostContext']);
        _post({'jsonrpc': '2.0', 'method': 'ui/notifications/initialized'});
        web.ResizeObserver(((JSAny _, JSAny _) => _measure()).toJS).observe(web.document.body!);
      case {'jsonrpc': '2.0', 'method': 'ui/notifications/tool-result', 'params': final Map<String, Object?> result}:
        _show(result);
      case {'jsonrpc': '2.0', 'method': 'ui/notifications/host-context-changed', 'params': final Object? context}:
        _context(context);
      case {'jsonrpc': '2.0', 'method': 'ui/resource-teardown' || 'ping', 'id': final Object id}:
        _post({'jsonrpc': '2.0', 'id': id, 'result': <String, Object?>{}});
      case {'jsonrpc': '2.0', 'method': String _, 'id': final Object id}:
        _post({
          'jsonrpc': '2.0',
          'id': id,
          'error': {'code': -32601, 'message': 'Method not found'},
        });
    }
  }

  void _show(Map<String, Object?> result) {
    setState(() => _result = result);
    // Measured as soon as the card is drawn, not left to the ResizeObserver: a
    // browser may throttle a cross-origin frame that is still a few pixels
    // tall, and the size report must not wait on it.
    Future(_measure);
  }

  void _context(Object? context) {
    if (context case final Map<String, Object?> context) {
      if (context['theme'] case final String theme when theme == 'light' || theme == 'dark') {
        web.document.documentElement!.setAttribute('data-theme', theme);
      }
      setState(() {
        _format = IntlFormat(
          locale: switch (context['locale']) {
            final String locale => locale,
            _ => _format.locale,
          },
          timeZone: switch (context['timeZone']) {
            final String timeZone => timeZone,
            _ => _format.timeZone,
          },
        );
      });
      if (_result != null) Future(_measure);
    }
  }

  void _measure() {
    final html = web.document.documentElement! as web.HTMLElement;
    final height = html.style.height;
    html.style.height = 'max-content';
    final h = html.getBoundingClientRect().height.ceil();
    html.style.height = height;
    final w = web.window.innerWidth;
    if (w == _lastWidth && h == _lastHeight) return;
    _lastWidth = w;
    _lastHeight = h;
    _post({
      'jsonrpc': '2.0',
      'method': 'ui/notifications/size-changed',
      'params': {'width': w, 'height': h},
    });
  }

  void _post(Map<String, Object?> message) => web.window.parent?.postMessage(message.jsify(), '*'.toJS);

  @override
  Component build(BuildContext context) {
    return switch (_result) {
      null => const .empty(),
      {'structuredContent': final Map<String, Object?> data, 'isError': != true} => component.card(data, _format),
      final result => p(classes: 'note', [.text(result.toText())]),
    };
  }
}

/// A JS value as JSON-shaped Dart (`Map<String, dynamic>`, `List`, `num`,
/// `String`), so cards match on plain map patterns. Anything that doesn't
/// survive `JSON.stringify` reads as null.
Object? _read(JSAny? value) {
  if (value == null) return null;
  final json = (globalContext['JSON'] as JSObject).callMethod<JSString?>('stringify'.toJS, value);
  return json == null ? null : jsonDecode(json.toDart);
}

extension on Map<String, Object?> {
  /// The result's text content, shown when there's nothing to draw: a tool
  /// error, or a host that sends no `structuredContent`.
  String toText() {
    if (this['content'] case final List content) {
      for (final item in content) {
        if (item case {'type': 'text', 'text': final String text}) return text;
      }
    }
    return 'Nothing to show.';
  }
}

/// [Format] over the browser's `Intl`, in the host's locale and time zone once
/// it has said them. An unknown locale or zone falls back to the browser's.
class IntlFormat implements Format {
  new({this.locale, this.timeZone});

  final String? locale;
  final String? timeZone;

  static JSObject get _intl => globalContext['Intl'] as JSObject;

  @override
  String number(num n, [int digits = 1]) {
    return _format('NumberFormat', {'maximumFractionDigits': digits}, n.toJS) ?? '$n';
  }

  @override
  String dateTime(String iso) {
    final date = (globalContext['Date'] as JSFunction).callAsConstructor<JSObject>(iso.toJS);
    final options = {
      'timeZone': ?timeZone,
      'weekday': 'long',
      'day': 'numeric',
      'month': 'short',
      'year': 'numeric',
      'hour': 'numeric',
      'minute': '2-digit',
    };
    return _format('DateTimeFormat', options, date) ?? iso;
  }

  String? _format(String formatter, Map<String, Object> options, JSAny value) {
    for (final (locale, options_) in [
      (locale, options),
      (null, {...options}..remove('timeZone')),
    ]) {
      try {
        final format = _intl.callMethodVarArgs<JSObject>(formatter.toJS, [locale?.toJS, options_.jsify()]);
        return format.callMethod<JSString>('format'.toJS, value).toDart;
      } catch (_) {
        // A RangeError from an unknown locale or time zone: try the defaults.
      }
    }
    return null;
  }
}
