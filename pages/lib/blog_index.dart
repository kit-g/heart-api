import 'package:jaspr/dom.dart';
import 'package:jaspr/server.dart';
import 'package:jaspr_content/jaspr_content.dart';

import 'posts.dart';

/// `<BlogIndex/>` in a page: every post, newest first.
class BlogIndex extends CustomComponent {
  new() : super.base();

  @override
  Component? create(Node node, NodesBuilder builder) {
    if (node case ElementNode(tag: 'BlogIndex')) {
      return Builder(
        builder: (context) => ul(classes: 'flex flex-col gap-8 mt-10', [
          for (final post in Post.all(context.pages))
            li([
              a(href: post.url, classes: 'group block', [
                h2(classes: 'font-title text-xl font-semibold group-hover:text-accent-ink transition-colors', [
                  .text(post.title),
                ]),
                p(classes: 'mt-1 text-muted', [.text(post.description)]),
                Component.element(
                  tag: 'time',
                  classes: 'block mt-1 text-sm text-faint',
                  attributes: {'datetime': post.date.toIsoDate()},
                  children: [.text(post.date.toDisplay())],
                ),
              ]),
            ]),
        ]),
      );
    }
    return null;
  }
}
