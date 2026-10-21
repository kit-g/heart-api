/// Builds heart-of.me's rendered pages to static HTML, for one environment:
/// `dart run jaspr_cli:jaspr build --dart-define=HEART_ENV=prod`, or `dev`,
/// the default. Today that is the blog:
/// `content/blog.html.md` is the index, shared by both sites, and each
/// `posts/<env>/blog/<slug>.html.md` a post on that environment's site only.
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
import 'posts.dart';
import 'site_layout.dart';

void main() {
  if (environment != 'dev' && environment != 'prod') {
    throw ArgumentError.value(environment, 'HEART_ENV', 'must be dev or prod');
  }
  Jaspr.initializeApp(options: defaultServerOptions);

  runApp(
    ContentApp.custom(
      loaders: [FilesystemLoader('content'), FilesystemLoader('posts/$environment')],
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
