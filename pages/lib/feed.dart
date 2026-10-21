import 'package:jaspr/server.dart';
import 'package:jaspr_content/jaspr_content.dart';

import 'posts.dart';

/// `/blog.xml`, the RSS feed, written beside the index.
///
/// Not jaspr_content's `RSSOutput`: that one only attaches to `index.*`
/// pages, doesn't escape titles, and dates items in a form RSS readers reject
/// (RSS wants RFC 822).
class BlogFeed extends SecondaryOutput {
  @override
  Pattern get pattern => RegExp(r'^blog\.html\.md$');

  @override
  String createRoute(String route) => '/blog.xml';

  @override
  Component build(Page page) {
    return Builder(
      builder: (context) {
        context.setHeader('Content-Type', 'application/rss+xml');
        context.setStatusCode(200, responseBody: _feed(Post.all(context.pages)));
        return const Component.text('');
      },
    );
  }

  String _feed(List<Post> posts) {
    final items = [
      for (final post in posts)
        '''
    <item>
      <title>${_escape(post.title)}</title>
      <link>$origin${post.url}</link>
      <guid>$origin${post.url}</guid>
      <description>${_escape(post.description)}</description>
      <pubDate>${post.date.toRfc822()}</pubDate>
    </item>''',
    ];
    return '''
<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0">
  <channel>
    <title>Heart of Yours blog</title>
    <link>$origin/blog.html</link>
    <description>Development stories and technical write-ups from Heart of Yours.</description>
    <language>en</language>
${items.join('\n')}
  </channel>
</rss>
''';
  }

  static String _escape(String text) => text.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');
}

extension on DateTime {
  static const _days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  static const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

  /// `Sun, 18 Oct 2026 00:00:00 GMT`. Posts carry a date only.
  String toRfc822() {
    final date = day.toString().padLeft(2, '0');
    return '${_days[weekday - 1]}, $date ${_months[month - 1]} $year 00:00:00 GMT';
  }
}
