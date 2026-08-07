import 'package:heart_aws/heart_aws.dart';
import 'package:test/test.dart';

import 'helpers/sigv4_reference.dart';

const _accessKeyId = 'AKIDEXAMPLE';
const _secretAccessKey = 'wJalrXUtnFEMI/K7MDENG+bPxRfiCYEXAMPLEKEY';
const _region = 'us-east-1';
const _provider = StaticCredentialsProvider(AWSCredentials(_accessKeyId, _secretAccessKey));

class _TestS3 extends S3Api {
  @override
  final String region = _region;

  @override
  final AWSCredentialsProvider credentialsProvider = _provider;
}

void main() {
  group('config', () {
    test('S3 uses the S3-specific service configuration', () {
      expect(_TestS3().config, isA<S3ServiceConfiguration>());
    });

    for (final (name, signer, service) in <(String, Signer, AWSService)>[
      ('Sqs', Sqs(credentialsProvider: _provider, region: _region), AWSService.sqs),
      ('Sns', Sns(credentialsProvider: _provider, region: _region), AWSService.sns),
      ('Scheduler', Scheduler(credentialsProvider: _provider, region: _region), AWSService.scheduler),
    ]) {
      test('$name uses the ${service.service} service with the base configuration', () {
        expect(signer.service, service);
        expect(signer.config, isA<BaseServiceConfiguration>());
        expect(signer.config, isNot(isA<S3ServiceConfiguration>()));
      });
    }
  });

  group('createPresignedUrl with the base configuration', () {
    test('produces a structurally valid presigned URL', () async {
      final scheduler = Scheduler(credentialsProvider: _provider, region: _region);
      final url = await scheduler.createPresignedUrl(
        method: AWSHttpMethod.get,
        uri: Uri.https('scheduler.us-east-1.amazonaws.com', '/schedules/test'),
        expiresIn: const Duration(minutes: 10),
      );
      final qp = url.queryParameters;

      expect(url.host, 'scheduler.us-east-1.amazonaws.com');
      expect(url.path, '/schedules/test');
      expect(qp['X-Amz-Algorithm'], 'AWS4-HMAC-SHA256');
      expect(qp['X-Amz-Date'], matches(RegExp(r'^\d{8}T\d{6}Z$')));
      expect(
        qp['X-Amz-Credential'],
        '$_accessKeyId/${qp['X-Amz-Date']!.substring(0, 8)}/$_region/scheduler/aws4_request',
      );
      expect(qp['X-Amz-Expires'], '600');
      expect(qp['X-Amz-SignedHeaders'], 'host');
      expect(qp['X-Amz-Signature'], matches(RegExp(r'^[0-9a-f]{64}$')));
    });

    test('signature matches an independent SigV4 implementation', () async {
      // The base configuration signs the (empty) payload, unlike S3's
      // UNSIGNED-PAYLOAD, so this exercises the other hashing branch.
      final scheduler = Scheduler(credentialsProvider: _provider, region: _region);
      final url = await scheduler.createPresignedUrl(
        method: AWSHttpMethod.get,
        uri: Uri.https('scheduler.us-east-1.amazonaws.com', '/schedules/test'),
        expiresIn: const Duration(minutes: 10),
      );
      final expected = recomputePresignedUrlSignature(
        url: url,
        secretAccessKey: _secretAccessKey,
        region: _region,
        service: 'scheduler',
        payloadHash: emptyPayloadSha256,
      );
      expect(url.queryParameters['X-Amz-Signature'], expected);
    });
  });
}
