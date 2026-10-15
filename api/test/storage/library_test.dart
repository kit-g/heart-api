import 'package:heart/storage/s3.dart';
import 'package:heart_aws/heart_aws.dart';
import 'package:test/test.dart';

/// [Storage] with the bucket replaced by [answers], one a read.
class _Bucket extends Storage {
  final List<Object> answers;
  final reads = <String>[];

  new(this.answers)
    : super(
        credentialsProvider: const AWSCredentialsProvider(AWSCredentials('AKIAEXAMPLE', 'secret')),
        region: 'us-east-1',
        contentBucket: 'content',
      );

  @override
  Future<String> getObject(String bucket, String key) async {
    reads.add('$bucket/$key');
    return switch (answers.removeAt(0)) {
      final String body => body,
      final Object error => throw error,
    };
  }
}

/// The program library read from the bucket the CDN serves (heart-api#259).
void main() {
  test('reads static/programs once, then keeps it', () async {
    final bucket = _Bucket(['{"version": 2, "programs": []}']);
    expect(await bucket.read(), {'version': 2, 'programs': []});
    expect(await bucket.read(), {'version': 2, 'programs': []});
    expect(bucket.reads, ['content/static/programs']);
  });

  test('a file not published yet, or not an object, is no library, not an error', () async {
    expect(await _Bucket([Exception('404')]).read(), isNull);
    expect(await _Bucket(['[]']).read(), isNull);
  });
}
