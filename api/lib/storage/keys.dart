import 'dart:convert';

import 'package:heart_aws/heart_aws.dart';

import '../models/imports.dart';

/// Where a workout image lives in the content bucket.
///
/// Two writers derive this key independently: the presign route promises the
/// destination URL to the client before the upload, and the upload event
/// handler copies the object there after. They must agree, or uploaded
/// objects and DB records diverge.
String workoutImageKey({
  required String userId,
  required String workoutId,
  required String imageId,
  required String ext,
}) {
  final hash = sha256.convert(utf8.encode('$userId:$workoutId')).toString().substring(0, 16);
  return 'workouts/$hash/$imageId.$ext';
}

/// Where an export the parser could not read waits for a manual import. The
/// content hash makes a retry of the same file the same object; the user
/// lives in the key only hashed, as for images.
String parkedImportKey({required String userId, required ImportSource source, required List<int> bytes}) {
  final user = sha256.convert(utf8.encode(userId)).toString().substring(0, 16);
  final content = sha256.convert(bytes).toString().substring(0, 16);
  return 'imports/parked/$user/${source.name}-$content.csv';
}
