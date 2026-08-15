import 'dart:convert';

import 'package:heart_aws/heart_aws.dart';
import 'package:test/test.dart';

import 'helpers/sigv4_reference.dart';

const _accessKeyId = 'AKIDEXAMPLE';
const _secretAccessKey = 'wJalrXUtnFEMI/K7MDENG+bPxRfiCYEXAMPLEKEY';
const _region = 'us-east-1';

class _TestS3 extends S3Api {
  @override
  final String region;

  @override
  final AWSCredentialsProvider credentialsProvider;

  new({
    this.region = _region,
    AWSCredentials credentials = const AWSCredentials(_accessKeyId, _secretAccessKey),
  }) : credentialsProvider = StaticCredentialsProvider(credentials);
}

void main() {
  group('s3Uri', () {
    for (final (key, expected) in <(String, String)>[
      ('file.txt', 'https://bucket.s3.us-east-1.amazonaws.com/file.txt'),
      ('/file.txt', 'https://bucket.s3.us-east-1.amazonaws.com/file.txt'),
      ('a/b/c.json', 'https://bucket.s3.us-east-1.amazonaws.com/a/b/c.json'),
      ('/a/b/c.json', 'https://bucket.s3.us-east-1.amazonaws.com/a/b/c.json'),
      ('a b.txt', 'https://bucket.s3.us-east-1.amazonaws.com/a%20b.txt'),
    ]) {
      test('maps key "$key" to $expected', () {
        expect(_TestS3().s3Uri('bucket', key).toString(), expected);
      });
    }

    test('uses the configured region in the host', () {
      final uri = _TestS3(region: 'eu-west-2').s3Uri('bucket', 'k');
      expect(uri.host, 'bucket.s3.eu-west-2.amazonaws.com');
    });
  });

  group('service configuration', () {
    test('uses the S3 service and configuration', () {
      final s3 = _TestS3();
      expect(s3.service, AWSService.s3);
      expect(s3.config, isA<S3ServiceConfiguration>());
    });
  });

  group('presigned URLs', () {
    test('getDownloadUrl produces a structurally valid presigned GET URL', () async {
      final url = await _TestS3().getDownloadUrl('bucket', 'some/file.txt');
      final qp = url.queryParameters;

      expect(url.scheme, 'https');
      expect(url.host, 'bucket.s3.us-east-1.amazonaws.com');
      expect(url.path, '/some/file.txt');
      expect(qp['X-Amz-Algorithm'], 'AWS4-HMAC-SHA256');
      expect(qp['X-Amz-Date'], matches(RegExp(r'^\d{8}T\d{6}Z$')));
      expect(qp['X-Amz-Credential'], '$_accessKeyId/${qp['X-Amz-Date']!.substring(0, 8)}/$_region/s3/aws4_request');
      expect(qp['X-Amz-Expires'], '300');
      expect(qp['X-Amz-SignedHeaders'], 'host');
      expect(qp['X-Amz-Signature'], matches(RegExp(r'^[0-9a-f]{64}$')));
    });

    for (final (expiresIn, expected) in <(Duration, String)>[
      (const Duration(minutes: 1), '60'),
      (const Duration(hours: 2), '7200'),
      (const Duration(days: 7), '604800'),
    ]) {
      test('getDownloadUrl encodes expiresIn=$expiresIn as X-Amz-Expires=$expected', () async {
        final url = await _TestS3().getDownloadUrl('bucket', 'k', expiresIn: expiresIn);
        expect(url.queryParameters['X-Amz-Expires'], expected);
      });
    }

    test('getDownloadUrl signs the content-type header when a mime type is given', () async {
      final url = await _TestS3().getDownloadUrl('bucket', 'k', mimeType: 'image/png');
      expect(url.queryParameters['X-Amz-SignedHeaders'], 'content-type;host');
    });

    test('getDownloadUrl ignores an empty mime type', () async {
      final url = await _TestS3().getDownloadUrl('bucket', 'k', mimeType: '');
      expect(url.queryParameters['X-Amz-SignedHeaders'], 'host');
    });

    test('getDownloadUrl signature matches an independent SigV4 implementation', () async {
      final url = await _TestS3().getDownloadUrl('bucket', 'some/file.txt');
      final expected = recomputePresignedUrlSignature(
        url: url,
        secretAccessKey: _secretAccessKey,
        region: _region,
        service: 's3',
        payloadHash: unsignedPayloadSha256,
      );
      expect(url.queryParameters['X-Amz-Signature'], expected);
    });

    test('getUploadUrl signature matches an independent SigV4 implementation', () async {
      final url = await _TestS3().getUploadUrl('bucket', 'uploads/photo.jpg');
      final expected = recomputePresignedUrlSignature(
        url: url,
        secretAccessKey: _secretAccessKey,
        region: _region,
        service: 's3',
        payloadHash: unsignedPayloadSha256,
        method: 'PUT',
      );
      expect(url.queryParameters['X-Amz-Signature'], expected);
    });

    test('presigned URL includes and signs the session token when present', () async {
      final s3 = _TestS3(credentials: const AWSCredentials(_accessKeyId, _secretAccessKey, 'the-session-token'));
      final url = await s3.getDownloadUrl('bucket', 'k');
      expect(url.queryParameters['X-Amz-Security-Token'], 'the-session-token');
      final expected = recomputePresignedUrlSignature(
        url: url,
        secretAccessKey: _secretAccessKey,
        region: _region,
        service: 's3',
        payloadHash: unsignedPayloadSha256,
      );
      expect(url.queryParameters['X-Amz-Signature'], expected);
    });
  });

  group('createPresignedPost', () {
    Map<String, dynamic> decodePolicy(String policyBase64) {
      return jsonDecode(utf8.decode(base64Decode(policyBase64))) as Map<String, dynamic>;
    }

    test('builds the bucket URL and the default form fields', () async {
      final (:url, :fields) = await _TestS3().createPresignedPost(bucket: 'bucket', key: 'uploads/file.txt');

      expect(url, 'https://bucket.s3.us-east-1.amazonaws.com/');
      expect(fields['key'], 'uploads/file.txt');
      expect(fields['x-amz-algorithm'], 'AWS4-HMAC-SHA256');
      expect(fields['x-amz-date'], matches(RegExp(r'^\d{8}T\d{6}Z$')));
      final date = fields['x-amz-date']!.substring(0, 8);
      expect(fields['x-amz-credential'], '$_accessKeyId/$date/$_region/s3/aws4_request');
      expect(fields['policy'], isNotEmpty);
      expect(fields['x-amz-signature'], matches(RegExp(r'^[0-9a-f]{64}$')));
      expect(fields.containsKey('x-amz-security-token'), isFalse);
    });

    test('policy contains the default conditions in order', () async {
      final (url: _, :fields) = await _TestS3().createPresignedPost(bucket: 'bucket', key: 'uploads/file.txt');
      final policy = decodePolicy(fields['policy']!);

      expect(policy['conditions'], [
        {'bucket': 'bucket'},
        {'key': 'uploads/file.txt'},
        {'x-amz-credential': fields['x-amz-credential']},
        {'x-amz-algorithm': 'AWS4-HMAC-SHA256'},
        {'x-amz-date': fields['x-amz-date']},
      ]);
    });

    test('policy expiration is now plus expiresIn, formatted without fractional seconds', () async {
      final before = DateTime.now().toUtc();
      const expiresIn = Duration(minutes: 30);
      final (url: _, :fields) = await _TestS3().createPresignedPost(
        bucket: 'bucket',
        key: 'k',
        expiresIn: expiresIn,
      );
      final after = DateTime.now().toUtc();

      final expiration = decodePolicy(fields['policy']!)['expiration'] as String;
      expect(expiration, matches(RegExp(r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$')));

      final parsed = DateTime.parse(expiration);
      expect(parsed.isBefore(before.add(expiresIn).subtract(const Duration(seconds: 1))), isFalse);
      expect(parsed.isAfter(after.add(expiresIn)), isFalse);
    });

    test(r'a key ending in ${filename} becomes a starts-with condition', () async {
      final (url: _, :fields) = await _TestS3().createPresignedPost(bucket: 'bucket', key: r'uploads/${filename}');
      final conditions = decodePolicy(fields['policy']!)['conditions'] as List;

      expect(fields['key'], r'uploads/${filename}');
      expect(conditions[1], ['starts-with', r'$key', 'uploads/']);
      expect(conditions.whereType<Map>().any((c) => c.containsKey('key')), isFalse);
    });

    test('custom fields and conditions are included', () async {
      final (url: _, :fields) = await _TestS3().createPresignedPost(
        bucket: 'bucket',
        key: 'k',
        fields: {'Content-Type': 'image/png', 'success_action_status': '201'},
        conditions: [
          {'Content-Type': 'image/png'},
          ['content-length-range', 0, 1048576],
        ],
      );
      final conditions = decodePolicy(fields['policy']!)['conditions'] as List;

      expect(fields['Content-Type'], 'image/png');
      expect(fields['success_action_status'], '201');
      expect(conditions.sublist(5), [
        {'Content-Type': 'image/png'},
        ['content-length-range', 0, 1048576],
      ]);
    });

    test('session token is added to the fields and as the last condition', () async {
      final s3 = _TestS3(credentials: const AWSCredentials(_accessKeyId, _secretAccessKey, 'the-session-token'));
      final (url: _, :fields) = await s3.createPresignedPost(
        bucket: 'bucket',
        key: 'k',
        conditions: [
          ['content-length-range', 0, 10],
        ],
      );
      final conditions = decodePolicy(fields['policy']!)['conditions'] as List;

      expect(fields['x-amz-security-token'], 'the-session-token');
      expect(conditions.last, {'x-amz-security-token': 'the-session-token'});
      expect(conditions[conditions.length - 2], ['content-length-range', 0, 10]);
    });

    test('signature is the SigV4 HMAC of the base64 policy', () async {
      final (url: _, :fields) = await _TestS3().createPresignedPost(bucket: 'bucket', key: 'uploads/file.txt');

      final date = fields['x-amz-date']!.substring(0, 8);
      final signingKey = deriveSigningKey(
        secretAccessKey: _secretAccessKey,
        date: date,
        region: _region,
        service: 's3',
      );
      expect(fields['x-amz-signature'], hexHmacSha256(signingKey, fields['policy']!));
    });
  });
}
