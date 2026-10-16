part of 's3.dart';

mixin _Library on _StorageBase implements ProgramLibrary {
  final _programs = _Held('static/programs', Logger('ProgramLibrary'));

  @override
  Future<Map<String, dynamic>?> read() => _programs.read(this);
}

mixin _Balance on _StorageBase implements BalancePairs {
  final _pairs = _Held('static/balance', Logger('BalancePairs'));

  @override
  Future<Map<String, dynamic>?> readPairs() => _pairs.read(this);
}

/// A CDN object read from the bucket it is served from, and held a while.
class _Held {
  final String _key;
  final Logger _logger;

  new(this._key, this._logger);

  /// How long an instance keeps what it read. The file changes by hand, rarely,
  /// and nothing needs a new one sooner.
  static const _lifetime = Duration(hours: 1);

  /// How soon a failed read is tried again.
  static const _retry = Duration(minutes: 5);

  ({DateTime at, Map<String, dynamic>? content})? _held;

  Future<Map<String, dynamic>?> read(_StorageBase storage) async {
    final now = DateTime.timestamp();
    if (_held case (:final at, :final content) when now.difference(at) < _lifetime) return content;
    try {
      final content = switch (jsonDecode(await storage.getObject(storage.contentBucket, _key))) {
        final Map<String, dynamic> content => content,
        _ => null,
      };
      _held = (at: now, content: content);
      return content;
    } catch (error) {
      // not published yet, or unreadable: a while without the content, not a
      // failed request; what was read before stays until it can be read again
      _logger.warning('$_key: $error');
      _held = (at: now.subtract(_lifetime - _retry), content: _held?.content);
      return _held?.content;
    }
  }
}
