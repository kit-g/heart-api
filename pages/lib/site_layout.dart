import 'dart:convert';

import 'package:jaspr/dom.dart';
import 'package:jaspr/server.dart';
import 'package:jaspr_content/jaspr_content.dart';

import 'posts.dart';

/// The site's chrome around a rendered page: the head every site page has,
/// the header and footer of `site/strong-alternative.html`, and the post or
/// index between them. Styling is the site's own `site.css` and Tailwind
/// build (whose `content` globs include this package), so light and dark
/// follow the OS as on every other page.
///
/// Links are root-absolute: these pages live under `/blog/`, and the site's
/// own pages use relative links that only work from the root.
class SiteLayout implements PageLayout {
  const new();

  @override
  Pattern get name => 'site';

  @override
  Component buildLayout(Page page, Component child) {
    final data = page.data.page;
    final post = page.url.startsWith('/blog/') ? Post.of(page) : null;
    final title = data['title'] as String;
    final description = data['description'] as String;
    final url = '$origin${page.url}';
    final image = post?.image ?? defaultImage;

    return Document(
      lang: 'en',
      // No <base>: a post's relative image resolves next to the post.
      base: null,
      title: '$title - Heart of Yours',
      head: [
        meta(name: 'description', content: description),
        link(rel: 'canonical', href: url),
        const link(rel: 'icon', type: 'image/png', href: '/assets/favicon.png', attributes: {'sizes': '256x256'}),
        const link(rel: 'apple-touch-icon', href: '/apple-touch-icon.png', attributes: {'sizes': '180x180'}),
        const link(
          rel: 'alternate',
          type: 'application/rss+xml',
          href: '/blog.xml',
          attributes: {'title': 'Heart of Yours blog'},
        ),
        meta(attributes: {'property': 'og:type', 'content': post == null ? 'website' : 'article'}),
        const meta(attributes: {'property': 'og:site_name', 'content': 'Heart of Yours'}),
        meta(attributes: {'property': 'og:title', 'content': title}),
        meta(attributes: {'property': 'og:description', 'content': description}),
        meta(attributes: {'property': 'og:url', 'content': url}),
        meta(attributes: {'property': 'og:image', 'content': image}),
        if (image == defaultImage) ...[
          const meta(attributes: {'property': 'og:image:width', 'content': '1200'}),
          const meta(attributes: {'property': 'og:image:height', 'content': '630'}),
          const meta(attributes: {'property': 'og:image:alt', 'content': defaultImageAlt}),
        ],
        if (post != null) meta(attributes: {'property': 'article:published_time', 'content': post.date.toIsoDate()}),
        const meta(name: 'twitter:card', content: 'summary_large_image'),
        if (post != null) _structuredData(post),
        const link(rel: 'preconnect', href: 'https://fonts.googleapis.com'),
        const link(rel: 'preconnect', href: 'https://fonts.gstatic.com', attributes: {'crossorigin': ''}),
        const link(
          rel: 'stylesheet',
          href:
              'https://fonts.googleapis.com/css2?family=IBM+Plex+Sans:wght@400;500;600'
              '&family=Literata:opsz,wght@7..72,600&display=swap',
        ),
        const link(
          rel: 'stylesheet',
          href:
              'https://fonts.googleapis.com/css2?family=Material+Symbols+Outlined:wght,FILL@100..700,0..1&display=swap',
        ),
        const link(rel: 'stylesheet', href: '/assets/site.css'),
        const link(rel: 'stylesheet', href: '/assets/tailwind.css'),
        const script(src: '/assets/site.js'),
      ],
      body: div(
        classes:
            'bg-ground text-ink font-text min-h-screen flex flex-col overflow-x-hidden '
            'selection:bg-accent selection:text-on-accent',
        [
          const _Header(),
          main_(classes: 'flex-grow w-full max-w-3xl mx-auto px-4 sm:px-6 py-12 md:py-16', [
            if (post != null)
              article([
                h1(classes: 'font-title text-3xl md:text-4xl font-semibold leading-tight', [.text(title)]),
                Component.element(
                  tag: 'time',
                  classes: 'block mt-3 text-muted',
                  attributes: {'datetime': post.date.toIsoDate()},
                  children: [.text(post.date.toDisplay())],
                ),
                div(
                  classes:
                      'prose prose-lg max-w-none mt-10 prose-code:before:content-none prose-code:after:content-none',
                  [child],
                ),
              ])
            else ...[
              h1(classes: 'font-title text-3xl md:text-4xl font-semibold leading-tight', [.text(title)]),
              p(classes: 'mt-3 text-muted', [.text(description)]),
              child,
            ],
          ]),
          const _Footer(),
        ],
      ),
    );
  }

  /// schema.org `BlogPosting`, so search results can show the date and title.
  Component _structuredData(Post post) => script(
    attributes: {'type': 'application/ld+json'},
    content: jsonEncode({
      '@context': 'https://schema.org',
      '@type': 'BlogPosting',
      'headline': post.title,
      'description': post.description,
      'datePublished': post.date.toIsoDate(),
      'image': post.image,
      'url': '$origin${post.url}',
      'publisher': {'@type': 'Organization', 'name': 'Heart of Yours', 'url': '$origin/'},
    }),
  );
}

const _links = [
  ('/features.html', 'Features'),
  ('/blog.html', 'Blog'),
  ('/privacy.html', 'Privacy'),
  ('/account.html', 'Account Control'),
];

class _Header extends StatelessComponent {
  const new();

  static const _navLink = 'text-sm font-medium text-muted hover:text-accent-ink transition-colors';

  @override
  Component build(BuildContext context) {
    return header(classes: 'w-full flex flex-col items-center pt-6 pb-2 px-6 sm:px-10 z-10', [
      div(classes: 'w-full max-w-[1200px] flex items-center justify-between', [
        const a(href: '/', classes: 'flex items-center gap-3 hover:opacity-80 transition-opacity', [
          div(classes: 'size-9 flex items-center justify-center bg-surface rounded overflow-hidden border', [
            // Two transparent marks drawn in --ink, as on every site page.
            Component.element(
              tag: 'picture',
              classes: 'size-full',
              children: [
                source(attributes: {'srcset': '/assets/logo-dark.png', 'media': '(prefers-color-scheme: dark)'}),
                img(
                  src: '/assets/logo-light.png',
                  width: 192,
                  height: 192,
                  alt: '',
                  classes: 'size-full object-contain',
                ),
              ],
            ),
          ]),
          h2(classes: 'text-lg font-title font-semibold tracking-tight', [.text('Heart of Yours')]),
        ]),
        nav(classes: 'hidden md:flex items-center gap-8', [
          for (final (href, label) in _links) a(href: href, classes: _navLink, [.text(label)]),
        ]),
        const button(
          id: 'menu-button',
          classes: 'md:hidden flex items-center justify-center size-10 rounded bg-fill text-ink',
          attributes: {'aria-expanded': 'false', 'aria-controls': 'mobile-nav', 'aria-label': 'Menu'},
          [
            span(classes: 'material-symbols-outlined', [.text('menu')]),
          ],
        ),
      ]),
      // site.js opens and closes it.
      nav(
        id: 'mobile-nav',
        classes:
            'md:hidden w-full max-w-[1200px] mt-4 flex flex-col border rounded-xl bg-surface divide-y divide-border',
        attributes: {'hidden': ''},
        [
          for (final (href, label) in _links)
            a(href: href, classes: 'px-4 py-3 text-sm font-medium text-ink', [.text(label)]),
        ],
      ),
    ]);
  }
}

class _Footer extends StatelessComponent {
  const new();

  static const _link = 'text-sm font-medium text-muted hover:text-accent-ink transition-colors';

  @override
  Component build(BuildContext context) {
    return const footer(classes: 'w-full py-10 px-6 border-t bg-ground mt-auto', [
      div(classes: 'max-w-[960px] mx-auto flex flex-col items-center gap-6', [
        div(classes: 'flex flex-col md:flex-row items-center gap-4 md:gap-8', [
          a(href: '/privacy.html', classes: '$_link flex items-center gap-1', [
            span(classes: 'material-symbols-outlined text-[16px]', [.text('shield')]),
            .text('Privacy Policy'),
          ]),
          a(href: '/terms.html', classes: _link, [.text('Terms of Service')]),
          a(href: '/account.html', classes: _link, [.text('Account Control')]),
          a(href: '/support.html', classes: _link, [.text('Support')]),
          a(href: '/developers.html', classes: _link, [.text('Developer API')]),
          a(href: 'mailto:info@heart-of.me', classes: _link, [.text('info@heart-of.me')]),
        ]),
        p(classes: 'text-xs text-muted', [
          .text('© '),
          span(id: 'footer-year', []),
          .text(' Heart of Yours. All rights reserved. Designed for peace of mind.'),
        ]),
      ]),
    ]);
  }
}
