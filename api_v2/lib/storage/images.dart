part of 's3.dart';

typedef Tag = (String, String);

extension on Tag {
  String get xml => '<Tag><Key>${$1}</Key><Value>${$2}</Value></Tag>';
}

mixin _Images on _StorageBase implements ApiImageStorageService {
  @override
  Future<PreSignedUrl> presignUpload({
    required String key,
    required String mimeType,
    List<Tag>? tags,
  }) async {
    final tagSet = tags?.map((t) => t.xml).join();

    return createPresignedPost(
      bucket: contentBucket,
      key: key,
      fields: {
        'Content-Type': mimeType,
        ...{
          'tagging': ?switch (tagSet) {
            String set when set.isNotEmpty => '<Tagging><TagSet>$set</TagSet></Tagging>',
            _ => null,
          },
        },
      },
      conditions: [
        {'Content-Type': mimeType},
        if (tagSet case String set when set.isNotEmpty) {'tagging': '<Tagging><TagSet>$set</TagSet></Tagging>'},
      ],
    );
  }

  @override
  Future<void> copyObject({required String fromKey, required String toKey}) {
    return put(
      uri: s3Uri(contentBucket, toKey),
      headers: {'x-amz-copy-source': '$contentBucket/$fromKey'},
    );
  }

  @override
  Future<void> deleteObject({required String key}) {
    return delete(uri: s3Uri(contentBucket, key));
  }
}
