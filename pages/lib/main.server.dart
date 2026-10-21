/// Builds heart-of.me's rendered pages to static HTML (`dart run jaspr_cli:jaspr
/// build`). Today that is the blog: `content/blog.html.md` is the index, and
/// each `content/blog/<slug>.html.md` a post.
///
/// Sources carry `.html` before `.md` because the apex is shared with the web
/// app: site pages end in `.html` and extensionless paths are the app's.
/// jaspr_content strips only the last extension, so a source's route is its
/// file name, and `jaspr build` writes a route with an extension as that file.
library;

import 'package:jaspr/server.dart';
import 'package:jaspr_content/jaspr_content.dart';
import 'package:jaspr_content/theme.dart';

import 'blog_index.dart';
import 'code_block.dart';
import 'feed.dart';
import 'main.server.options.dart';
import 'site_layout.dart';

void main() {
  Jaspr.initializeApp(options: defaultServerOptions);

  runApp(
    ContentApp.custom(
      loaders: [FilesystemLoader('content')],
      // The index and the feed list every post, so every page loads first.
      eagerlyLoadAllPages: true,
      configResolver: PageConfig.all(
        parsers: [const MarkdownParser()],
        components: [CodeBlock(), BlogIndex()],
        layouts: [const SiteLayout()],
        secondaryOutputs: [BlogFeed()],
        theme: const ContentTheme.none(),
      ),
    ),
  );
}
