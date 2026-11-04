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

  /// `MESSAGE_TAG_KEYS`: `id:base64,id:base64`, newest first.
  static MessageTags? parse(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    final keys = <String, List<int>>{};
    for (final entry in raw.split(',')) {
      switch (entry.split(':')) {
        case [final id, final key]:
          keys[id] = base64.decode(key);
        default:
          throw ArgumentError('MESSAGE_TAG_KEYS must be id:base64 pairs');
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
    final expected = this.tag(
      commitment: commitment,
      senderId: senderId,
      recipientId: recipientId,
      at: at,
      keyId: tagKey,
    );
    if (expected != tag) return false;
    return base64.encode(Hmac(sha256, base64.decode(reporterKey)).convert(utf8.encode(words)).bytes) == commitment;
  }
}

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
