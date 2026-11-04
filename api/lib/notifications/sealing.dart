import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart' as sealing;

/// The server's side of genuine reports: a tag over what a sender committed to,
/// that the server can check later without having been able to read the words.
class MessageTags {
  /// By key id. The first is what new tags use, and the rest still check.
  final Map<String, List<int>> keys;

  const new(this.keys);

  /// `MESSAGE_TAG_KEYS`: `id:base64,id:base64`, newest first. A value that isn't
  /// that reads as unset, as any optional setting does: messages and reports
  /// answer 501, and every other route keeps working.
  static MessageTags? parse(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    final keys = <String, List<int>>{};
    for (final entry in raw.split(',')) {
      switch (entry.split(':')) {
        case [final id, final key] when id.isNotEmpty && key.isNotEmpty:
          try {
            keys[id] = base64.decode(key);
          } on FormatException {
            return null;
          }
        default:
          return null;
      }
    }
    return MessageTags(keys);
  }

  String get currentKey => keys.keys.first;

  String tag({
    required String commitment,
    required String senderId,
    required String recipientId,
    required DateTime at,
    String? keyId,
  }) {
    final key = keys[keyId ?? currentKey]!;
    final bytes = [
      ...base64.decode(commitment),
      ...utf8.encode('$senderId|$recipientId|${at.toUtc().toIso8601String()}'),
    ];
    return base64.encode(Hmac(sha256, key).convert(bytes).bytes);
  }

  /// That [senderId] sent [words] to [recipientId]: the tag holds them to the
  /// commitment, and the reporter's key ties the commitment to these words.
  ///
  /// Anything that isn't base64 is a message that doesn't check out, never a
  /// refused report: the reporter's key travels inside the sender's ciphertext,
  /// so a sender could otherwise make their own messages unreportable. Bytes are
  /// compared, in constant time, so either base64 alphabet checks the same.
  bool confirms({
    required String words,
    required String reporterKey,
    required String commitment,
    required String tag,
    required String tagKey,
    required String senderId,
    required String recipientId,
    required DateTime at,
  }) {
    if (!keys.containsKey(tagKey)) return false;
    try {
      final expected = this.tag(
        commitment: commitment,
        senderId: senderId,
        recipientId: recipientId,
        at: at,
        keyId: tagKey,
      );
      if (!_same(base64.decode(expected), base64.decode(tag))) return false;
      final committed = Hmac(sha256, base64.decode(reporterKey)).convert(utf8.encode(words)).bytes;
      return _same(committed, base64.decode(commitment));
    } on FormatException {
      return false;
    }
  }

  /// That [messages] are between [reporterId] and [reportedId], include at least
  /// one that [reportedId] sent, and every one checks out. Someone reporting
  /// themselves verifies nothing.
  bool verifies({required String reporterId, required String reportedId, required List<ReportedMessage> messages}) {
    if (reporterId == reportedId) return false;
    final people = {reporterId, reportedId};
    return messages.any((message) => message.senderId == reportedId) &&
        messages.every(
          (message) =>
              {message.senderId, message.recipientId}.containsAll(people) &&
              confirms(
                words: message.words,
                reporterKey: message.key,
                commitment: message.commitment,
                tag: message.tag,
                tagKey: message.tagKey,
                senderId: message.senderId,
                recipientId: message.recipientId,
                at: message.createdAt,
              ),
        );
  }
}

/// Whether two digests are equal, looking at every byte whatever the first difference.
bool _same(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  var difference = 0;
  for (var i = 0; i < a.length; i++) {
    difference |= a[i] ^ b[i];
  }
  return difference == 0;
}

/// One message a report carries: what the device opened, and what proves it.
typedef ReportedMessage = ({
  String words,
  String key,
  String commitment,
  String tag,
  String tagKey,
  String senderId,
  String recipientId,
  DateTime createdAt,
});

/// Seals [plaintext] to a public key whose private half isn't on the server: X25519
/// with a throwaway key, HKDF-SHA256 and ChaCha20-Poly1305. `scripts/open_report.py`
/// opens it. Base64 of the throwaway public key, the nonce, the ciphertext and the
/// tag, in that order.
Future<String> sealTo(String publicKeyBase64, String plaintext) async {
  final exchange = sealing.X25519();
  final ephemeral = await exchange.newKeyPair();
  final shared = await exchange.sharedSecretKey(
    keyPair: ephemeral,
    remotePublicKey: sealing.SimplePublicKey(base64.decode(publicKeyBase64), type: sealing.KeyPairType.x25519),
  );
  final key = await sealing.Hkdf(hmac: sealing.Hmac.sha256(), outputLength: 32).deriveKey(
    secretKey: shared,
    nonce: const [],
    info: utf8.encode('heart-report'),
  );
  final box = await sealing.Chacha20.poly1305Aead().encrypt(utf8.encode(plaintext), secretKey: key);
  final public = await ephemeral.extractPublicKey();
  return base64.encode(
    Uint8List.fromList([...public.bytes, ...box.nonce, ...box.cipherText, ...box.mac.bytes]),
  );
}
