import 'package:jaspr/dom.dart';
import 'package:jaspr/server.dart';
import 'package:jaspr_content/jaspr_content.dart';
import 'package:syntax_highlight_lite/syntax_highlight_lite.dart' hide Color;

/// Fenced code, highlighted at build time into `tok-*` classes rather than
/// jaspr_content's inline colours: the classes take the site's tokens, so
/// code follows light and dark like the rest of the page, and nothing ships
/// to the browser (the stock block adds a client-side copy button).
///
/// Only Dart has a grammar; other languages render plain.
class CodeBlock extends CustomComponent {
  new() : super.base();

  static HighlighterTheme? _theme;

  @override
  Component? create(Node node, NodesBuilder builder) {
    return switch (node) {
      ElementNode(
        tag: 'pre',
        children: [ElementNode(tag: 'code', :final children, attributes: {'class': 'language-dart'})],
      ) =>
        AsyncBuilder(
          builder: (context) async {
            await Highlighter.initialize(['dart']);
            // The highlighter needs a theme to run; only the scopes are used.
            final highlighter = Highlighter(language: 'dart', theme: _theme ??= await HighlighterTheme.loadDarkTheme());
            final source = children?.map((c) => c.innerText).join() ?? '';
            return pre([
              code(classes: 'language-dart', [_span(highlighter.highlight(source))]),
            ]);
          },
        ),
      _ => null,
    };
  }

  Component _span(TextSpan span) {
    final text = [
      if (span.text case final text?) Component.text(text),
      for (final child in span.children) _span(child),
    ];
    return switch (_kind(span.scopes)) {
      final kind? => Component.element(tag: 'span', classes: 'tok-$kind', children: text),
      null => Component.fragment(text),
    };
  }

  /// The TextMate scope, narrowed to the few kinds the stylesheet colours.
  static String? _kind(List<String> scopes) {
    for (final scope in scopes.reversed) {
      if (scope.startsWith('comment')) return 'comment';
      if (scope.startsWith('string')) return 'string';
      if (scope.startsWith('constant')) return 'constant';
      if (scope.startsWith('keyword') || scope.startsWith('storage')) return 'keyword';
      if (scope.startsWith('support.class') || scope.startsWith('entity.name')) return 'type';
    }
    return null;
  }
}
