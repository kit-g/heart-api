part of 'client.dart';

/// How long a signed client secret is good for.
///
/// Apple's ceiling is six months; each secret here is minted for one call and
/// thrown away, so minutes are generous. The short window is the reason the
/// secret can be built on demand rather than cached and rotated.
const _secretLifetime = Duration(minutes: 5);

/// The Sign in with Apple `.p8`, and the ES256 client secrets it signs.
///
/// The key is kept in the form Apple issues it — PEM-wrapped PKCS#8 — so that
/// rotating it is pasting a new file into the secret rather than converting
/// one. Parsing it back into a signing key is this class's whole job.
class AppleSignInKey {
  final ECPrivateKey _key;

  /// Apple Developer team id: the `iss` of every secret this signs.
  final String teamId;

  /// Names which of the team's keys signed it, as the `kid` header.
  final String keyId;

  const new _({required this._key, required this.teamId, required this.keyId});

  /// Reads the `.p8` at [pem].
  ///
  /// Throws if it is not a PKCS#8 EC private key — which is a configuration
  /// error, caught by the first call rather than at startup, because an
  /// environment without Apple configured must still boot.
  factory parse({required String pem, required String teamId, required String keyId}) {
    return AppleSignInKey._(key: _privateKey(pem), teamId: teamId, keyId: keyId);
  }

  /// A client secret JWT naming [clientId] as its subject.
  ///
  /// Apple checks `sub` against the `client_id` of the call it accompanies, so
  /// a secret is only ever good for the one client it was asked for.
  String clientSecretFor(String clientId, {DateTime? issuedAt}) {
    final now = issuedAt ?? DateTime.now();

    final header = _segment({'alg': 'ES256', 'kid': keyId});
    final payload = _segment({
      'iss': teamId,
      'iat': now.millisecondsSinceEpoch ~/ 1000,
      'exp': now.add(_secretLifetime).millisecondsSinceEpoch ~/ 1000,
      'aud': _appleId,
      'sub': clientId,
    });

    final signingInput = '$header.$payload';
    final signer = ECDSASigner(SHA256Digest(), HMac(SHA256Digest(), 64))
      ..init(true, PrivateKeyParameter<ECPrivateKey>(_key));

    // RFC 6979 deterministic k, hence the HMAC above: a Lambda has no entropy
    // worth trusting at cold start, and a repeated k on ECDSA leaks the key.
    final signature = signer.generateSignature(utf8.encode(signingInput)) as ECSignature;

    // JWS wants the raw pair, each padded to the curve's 32 bytes — not the
    // DER encoding `ECSignature` would suggest.
    return '$signingInput.${_base64Url([..._octets(signature.r), ..._octets(signature.s)])}';
  }

  static String _segment(Map<String, dynamic> json) => _base64Url(utf8.encode(jsonEncode(json)));

  static String _base64Url(List<int> bytes) => base64Url.encode(bytes).replaceAll('=', '');

  /// [value] as a fixed-width 32-byte big-endian string, the P-256 field size.
  static List<int> _octets(BigInt value) {
    final out = Uint8List(32);
    var remaining = value;
    for (var i = 31; i >= 0; i--) {
      out[i] = (remaining & BigInt.from(0xff)).toInt();
      remaining = remaining >> 8;
    }
    return out;
  }

  /// Digs the private scalar out of a PKCS#8 wrapper.
  ///
  /// `PrivateKeyInfo` holds the algorithm identifier and then an OCTET STRING
  /// whose contents are a whole second DER document, `ECPrivateKey`, whose
  /// second element is the scalar. Hence the two parses.
  static ECPrivateKey _privateKey(String pem) {
    final body = pem.split('\n').where((line) => !line.startsWith('-----')).join().replaceAll(RegExp(r'\s'), '');

    final info = ASN1Parser(base64.decode(body)).nextObject();
    final wrapped = switch (info) {
      ASN1Sequence(elements: [_, _, final ASN1OctetString key, ...]) => key,
      _ => throw const FormatException('not a PKCS#8 private key'),
    };

    final scalar = switch (ASN1Parser(wrapped.octets).nextObject()) {
      ASN1Sequence(elements: [_, final ASN1OctetString d, ...]) => d.octets,
      _ => throw const FormatException('not an EC private key'),
    };

    return ECPrivateKey(
      BigInt.parse(scalar.map((b) => b.toRadixString(16).padLeft(2, '0')).join(), radix: 16),
      ECCurve_prime256v1(),
    );
  }
}
