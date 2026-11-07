import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:heart/notifications/sealing.dart';
import 'package:test/test.dart';

void main() {
  final tags = MessageTags.parse('new:${base64.encode(List.filled(32, 1))},old:${base64.encode(List.filled(32, 2))}')!;
  final at = DateTime.utc(2026, 11);
  final reporterKey = base64.encode(List.filled(32, 7));

  String commit(String words) {
    return base64.encode(Hmac(sha256, base64.decode(reporterKey)).convert(utf8.encode(words)).bytes);
  }

  String tagFor(String commitment, {String sender = 'coach', String recipient = 'student'}) {
    return tags.tag(commitment: commitment, senderId: sender, recipientId: recipient, at: at);
  }

  bool confirm({
    String words = 'words',
    String? commitment,
    String? tag,
    String tagKey = 'new',
    String sender = 'coach',
    String recipient = 'student',
  }) {
    final committed = commitment ?? commit('words');
    return tags.confirms(
      words: words,
      reporterKey: reporterKey,
      commitment: committed,
      tag: tag ?? tagFor(committed),
      tagKey: tagKey,
      senderId: sender,
      recipientId: recipient,
      at: at,
    );
  }

  group('a genuine report', () {
    test('confirms who sent what', () => expect(confirm(), isTrue));
    test('altered words fail', () => expect(confirm(words: 'other words'), isFalse));
    test('a blamed third person fails', () => expect(confirm(sender: 'someone else'), isFalse));
    test('a different recipient fails', () => expect(confirm(recipient: 'someone else'), isFalse));
    test('an unknown key fails', () => expect(confirm(tagKey: 'gone'), isFalse));

    test('a rotated key still checks what it tagged', () {
      final committed = commit('words');
      final old = tags.tag(commitment: committed, senderId: 'coach', recipientId: 'student', at: at, keyId: 'old');
      expect(confirm(commitment: committed, tag: old, tagKey: 'old'), isTrue);
      expect(tags.currentKey, 'new');
    });
  });

  group('what a sender controls', () {
    test('a key that isn\'t base64 fails the message, and refuses nothing', () {
      final committed = commit('words');
      expect(
        tags.confirms(
          words: 'words',
          reporterKey: 'not base64!',
          commitment: committed,
          tag: tagFor(committed),
          tagKey: 'new',
          senderId: 'coach',
          recipientId: 'student',
          at: at,
        ),
        isFalse,
      );
    });

    test('a commitment or tag that isn\'t base64 fails the message', () {
      expect(confirm(commitment: 'not base64!', tag: tagFor(commit('words'))), isFalse);
      expect(confirm(tag: 'not base64!'), isFalse);
    });

    test('a commitment sent in the URL-safe alphabet checks like the standard one', () {
      // a commitment with a '+' in it, which the URL-safe alphabet writes as '-'
      var words = 'words 0';
      for (var i = 1; !commit(words).contains('+'); i++) {
        words = 'words $i';
      }
      final standard = commit(words);
      final urlSafe = standard.replaceAll('+', '-').replaceAll('/', '_');
      expect(confirm(words: words, commitment: urlSafe, tag: tagFor(urlSafe)), isTrue);
    });
  });

  group('a report', () {
    ReportedMessage message({String from = 'coach', String to = 'student'}) {
      final committed = commit('words');
      return (
        words: 'words',
        key: reporterKey,
        commitment: committed,
        tag: tagFor(committed, sender: from, recipient: to),
        tagKey: 'new',
        senderId: from,
        recipientId: to,
        createdAt: at,
      );
    }

    test('of what the reported person sent the reporter verifies', () {
      expect(tags.verifies(reporterId: 'student', reportedId: 'coach', messages: [message()]), isTrue);
    });

    test('about oneself verifies nothing', () {
      expect(
        tags.verifies(reporterId: 'coach', reportedId: 'coach', messages: [message()]),
        isFalse,
      );
    });
  });

  test('no keys configured reads as none, and so does a value that isn\'t keys', () {
    expect(MessageTags.parse(null), isNull);
    expect(MessageTags.parse(''), isNull);
    expect(MessageTags.parse('not-a-pair'), isNull);
    expect(MessageTags.parse('a:${base64.encode(List.filled(32, 1))},'), isNull);
    expect(MessageTags.parse('a:not base64!'), isNull);
  });

  test('sealing writes the throwaway key, the nonce, and the box, and differs each time', () async {
    final publicKey = base64.encode(List.filled(32, 9));
    final one = base64.decode(await sealTo(publicKey, 'words'));
    final two = base64.decode(await sealTo(publicKey, 'words'));
    expect(one.length, 32 + 12 + 'words'.length + 16);
    expect(one.sublist(0, 32), isNot(two.sublist(0, 32)));
  });
}
