part of '../heart_aws.dart';

const _expiresIn = Duration(minutes: 5);

abstract class S3Api with Signer {
  new();

  @override
  AWSService get service => .s3;

  Uri s3Uri(String bucket, String key) {
    return Uri.https('$bucket.s3.$region.amazonaws.com', key.startsWith('/') ? key.substring(1) : key);
  }

  Future<String> getObject(String bucket, String key) async {
    return get(uri: s3Uri(bucket, key));
  }

  /// Generates a temporary URL to download an object
  Future<Uri> getDownloadUrl(String bucket, String key, {Duration? expiresIn, String? mimeType}) async {
    return createPresignedUrl(
      method: .get,
      uri: s3Uri(bucket, key),
      expiresIn: expiresIn ?? _expiresIn,
      headers: switch (mimeType) {
        String s when s.isNotEmpty => {AWSHeaders.contentType: mimeType},
        _ => null,
      },
    );
  }

  /// Generates a temporary URL allowing a client to upload a file directly to S3
  Future<Uri> getUploadUrl(String bucket, String key, {Duration? expiresIn}) async {
    return createPresignedUrl(
      method: .put,
      uri: s3Uri(bucket, key),
      expiresIn: expiresIn ?? _expiresIn,
    );
  }

  List<int> _sign(List<int> key, String msg) => Hmac(sha256, key).convert(utf8.encode(msg)).bytes;

  /// Builds the URL and the form fields used for a presigned S3 POST.
  /// Modeled after boto3's generate_presigned_post.
  ///
  /// https://docs.aws.amazon.com/boto3/latest/reference/services/s3/client/generate_presigned_post.html
  Future<({String url, Map<String, String> fields})> createPresignedPost({
    required String bucket,
    required String key,
    Map<String, String>? fields,
    List<dynamic>? conditions,
    Duration expiresIn = const Duration(minutes: 15),
  }) async {
    final creds = await credentialsProvider.retrieve();
    final now = DateTime.now().toUtc();
    final date = '${now.year.pad(4)}${now.month.pad()}${now.day.pad()}';
    final amzDate = '${date}T${now.hour.pad()}${now.minute.pad()}${now.second.pad()}Z';
    final credentialStr = '${creds.accessKeyId}/$date/$region/s3/aws4_request';

    final expiration = '${now.add(expiresIn).toIso8601String().split('.').first}Z';

    final policyConditions = <dynamic>[
      {'bucket': bucket},
      if (key.endsWith(r'${filename}')) ['starts-with', r'$key', key.substring(0, key.length - 11)] else {'key': key},
      {'x-amz-credential': credentialStr},
      {'x-amz-algorithm': 'AWS4-HMAC-SHA256'},
      {'x-amz-date': amzDate},
      ...?conditions,
      if (creds.sessionToken case String token) {'x-amz-security-token': token},
    ];

    final formFields = <String, String>{
      'key': key,
      'x-amz-algorithm': 'AWS4-HMAC-SHA256',
      'x-amz-credential': credentialStr,
      'x-amz-date': amzDate,
      ...?fields,
      if (creds.sessionToken case String token) 'x-amz-security-token': token,
    };

    final policy = {
      'expiration': expiration,
      'conditions': policyConditions,
    };
    final policyBase64 = base64Encode(utf8.encode(jsonEncode(policy)));
    formFields['policy'] = policyBase64;

    var signingKey = _sign(utf8.encode('AWS4${creds.secretAccessKey}'), date);
    signingKey = _sign(signingKey, region);
    signingKey = _sign(signingKey, 's3');
    signingKey = _sign(signingKey, 'aws4_request');

    final signature = Hmac(sha256, signingKey).convert(utf8.encode(policyBase64)).toString();
    formFields['x-amz-signature'] = signature;

    return (url: 'https://$bucket.s3.$region.amazonaws.com/', fields: formFields);
  }

  Future<Map<String, String>> getObjectTagging(String bucket, String key) async {
    final uri = s3Uri(bucket, key).replace(query: 'tagging');
    final responseStr = await get(uri: uri);

    final tags = <String, String>{};
    // `[^<]*` on the value: a tag with an empty value is still a tag
    final tagRegExp = RegExp(r'<Key>([^<]+)</Key>\s*<Value>([^<]*)</Value>');

    for (final match in tagRegExp.allMatches(responseStr)) {
      if (match.groupCount == 2) {
        tags[match.group(1)!] = match.group(2)!;
      }
    }

    return tags;
  }
}
