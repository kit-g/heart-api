import 'dart:convert';

import 'package:heart/storage/s3.dart';
import 'package:heart_aws/heart_aws.dart';
import 'package:test/test.dart';

/// Field/condition construction for `presignUpload` (`storage/images.dart`).
/// Signing is pure local crypto over static credentials — nothing here touches
/// the network.
void main() {
  final storage = Storage(
    credentialsProvider: const AWSCredentialsProvider(AWSCredentials('AKIAEXAMPLE', 'secret')),
    region: 'us-east-1',
    contentBucket: 'content',
  );

  List<dynamic> policyConditions(Map<String, String> fields) {
    final policy = jsonDecode(utf8.decode(base64Decode(fields['policy']!))) as Map;
    return policy['conditions'] as List;
  }

  group('presignUpload', () {
    test('builds the standard post fields with the Content-Type', () async {
      final presigned = await storage.presignUpload(key: 'workouts/w1/img.jpg', mimeType: 'image/jpeg');

      expect(presigned.url, 'https://content.s3.us-east-1.amazonaws.com/');
      expect(presigned.fields, containsPair('key', 'workouts/w1/img.jpg'));
      expect(presigned.fields, containsPair('Content-Type', 'image/jpeg'));
      expect(presigned.fields, contains('policy'));
      expect(presigned.fields, contains('x-amz-signature'));
      expect(policyConditions(presigned.fields), contains(equals({'Content-Type': 'image/jpeg'})));
    });

    test('omits the tagging field and condition when there are no tags', () async {
      final presigned = await storage.presignUpload(key: 'k', mimeType: 'image/jpeg');

      expect(presigned.fields, isNot(contains('tagging')));
      for (final condition in policyConditions(presigned.fields)) {
        expect(condition, isNot(contains('tagging')));
      }
    });

    test('treats an empty tag list like no tags', () async {
      final presigned = await storage.presignUpload(key: 'k', mimeType: 'image/jpeg', tags: const []);
      expect(presigned.fields, isNot(contains('tagging')));
    });

    test('encodes tags as a Tagging XML document in both field and condition', () async {
      final presigned = await storage.presignUpload(
        key: 'k',
        mimeType: 'image/png',
        tags: const [('workoutId', 'w1'), ('userId', 'u1')],
      );

      const xml =
          '<Tagging><TagSet>'
          '<Tag><Key>workoutId</Key><Value>w1</Value></Tag>'
          '<Tag><Key>userId</Key><Value>u1</Value></Tag>'
          '</TagSet></Tagging>';
      expect(presigned.fields, containsPair('tagging', xml));
      expect(policyConditions(presigned.fields), contains(equals({'tagging': xml})));
    });
  });
}
