/// A minimal, independent reference implementation of the AWS Signature
/// Version 4 algorithm, used to verify signatures produced by the package
/// without any network calls.
///
/// https://docs.aws.amazon.com/IAM/latest/UserGuide/create-signed-request.html
library;

import 'dart:convert';

import 'package:heart_aws/heart_aws.dart';

/// The SHA-256 hex hash of an empty payload.
const emptyPayloadSha256 = 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855';

/// The payload hash S3 uses for presigned URLs.
const unsignedPayloadSha256 = 'UNSIGNED-PAYLOAD';

List<int> hmacSha256(List<int> key, String message) => Hmac(sha256, key).convert(utf8.encode(message)).bytes;

String hexHmacSha256(List<int> key, String message) => Hmac(sha256, key).convert(utf8.encode(message)).toString();

/// Derives the SigV4 signing key: HMAC chain over date, region, service and
/// the `aws4_request` termination string, seeded with `AWS4<secret>`.
List<int> deriveSigningKey({
  required String secretAccessKey,
  required String date,
  required String region,
  required String service,
}) {
  var key = hmacSha256(utf8.encode('AWS4$secretAccessKey'), date);
  key = hmacSha256(key, region);
  key = hmacSha256(key, service);
  return hmacSha256(key, 'aws4_request');
}

String _canonicalEncode(String component) => Uri.encodeQueryComponent(component).replaceAll('+', '%20');

/// Recomputes the signature for a presigned GET [url] whose only signed
/// header is `host`, from first principles. Comparing the result against the
/// URL's own `X-Amz-Signature` verifies the full signing pipeline.
String recomputePresignedUrlSignature({
  required Uri url,
  required String secretAccessKey,
  required String region,
  required String service,
  required String payloadHash,
  String method = 'GET',
}) {
  final parameters = Map.of(url.queryParameters)..remove('X-Amz-Signature');
  final encoded = parameters.entries.map((e) => MapEntry(_canonicalEncode(e.key), _canonicalEncode(e.value))).toList()
    ..sort((a, b) => a.key.compareTo(b.key));
  final canonicalQuery = encoded.map((e) => '${e.key}=${e.value}').join('&');

  final canonicalRequest = [
    method,
    url.path.isEmpty ? '/' : url.path,
    canonicalQuery,
    'host:${url.host}',
    '',
    'host',
    payloadHash,
  ].join('\n');

  final amzDate = url.queryParameters['X-Amz-Date']!;
  final date = amzDate.substring(0, 8);
  final scope = '$date/$region/$service/aws4_request';
  final stringToSign = [
    'AWS4-HMAC-SHA256',
    amzDate,
    scope,
    sha256.convert(utf8.encode(canonicalRequest)).toString(),
  ].join('\n');

  final signingKey = deriveSigningKey(
    secretAccessKey: secretAccessKey,
    date: date,
    region: region,
    service: service,
  );
  return hexHmacSha256(signingKey, stringToSign);
}
