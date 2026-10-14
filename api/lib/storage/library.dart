part of 's3.dart';

mixin _Library on _StorageBase implements ProgramLibrary {
  /// The CDN's object, read from the bucket it is served from.
  static const _key = 'static/programs';

  /// How long an instance keeps what it read. The file changes by hand, rarely,
  /// and nothing needs a new one sooner.
  static const _lifetime = Duration(hours: 1);

  /// How soon a failed read is tried again.
  static const _retry = Duration(minutes: 5);

  static final _logger = Logger('ProgramLibrary');

  ({DateTime at, Map<String, dynamic>? content})? _held;

  @override
  Future<Map<String, dynamic>?> read() async {
    final now = DateTime.timestamp();
    if (_held case (:final at, :final content) when now.difference(at) < _lifetime) return content;
    try {
      final content = switch (jsonDecode(await getObject(contentBucket, _key))) {
        final Map<String, dynamic> content => content,
        _ => null,
      };
      _held = (at: now, content: content);
      return content;
    } catch (error) {
      // not published yet, or unreadable: a while without the library, not a
      // failed request; what was read before stays until it can be read again
      _logger.warning('$_key: $error');
      _held = (at: now.subtract(_lifetime - _retry), content: _held?.content);
      return _held?.content;
    }
  }
}
