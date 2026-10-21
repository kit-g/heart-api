import 'package:jaspr_content/jaspr_content.dart';

/// The site's origin: link previews and feeds need absolute URLs, because
/// crawlers don't resolve relative ones.
const origin = 'https://heart-of.me';

/// The image a page shows in link previews unless it names its own.
const defaultImage = '$origin/assets/og.png?v=3';

/// A post's frontmatter, read once for the layout, the index and the feed.
///
/// `date` is written as `2026-10-18`, which YAML hands over as a string.
class Post {
  const new _(this.url, this.title, this.description, this.date, this.image);

  /// Fails the build, naming the page, when the frontmatter is incomplete.
  factory of(Page page) {
    return switch (page.data.page) {
      {'title': final String title, 'description': final String description, 'date': final String date}
          when DateTime.tryParse(date) != null =>
        Post._(
          page.url,
          title,
          description,
          DateTime.parse(date),
          switch (page.data.page['image']) {
            final String image when image.startsWith('/') => '$origin$image',
            final String image => '$origin${page.url.substring(0, page.url.lastIndexOf('/') + 1)}$image',
            _ => defaultImage,
          },
        ),
      _ => throw StateError('${page.path}: a post needs title, description and date (YYYY-MM-DD) in its frontmatter'),
    };
  }

  final String url;
  final String title;
  final String description;
  final DateTime date;
  final String image;

  /// Newest first.
  static List<Post> all(List<Page> pages) => [
    for (final page in pages)
      if (page.url.startsWith('/blog/')) Post.of(page),
  ]..sort((a, b) => b.date.compareTo(a.date));
}

extension PostDates on DateTime {
  static const _months = [
    'January', 'February', 'March', 'April', 'May', 'June', //
    'July', 'August', 'September', 'October', 'November', 'December',
  ];

  /// `18 October 2026`, as the site writes dates.
  String toDisplay() => '$day ${_months[month - 1]} $year';

  /// `2026-10-18`, for `<time datetime>` and `article:published_time`.
  String toIsoDate() => toIso8601String().substring(0, 10);
}
