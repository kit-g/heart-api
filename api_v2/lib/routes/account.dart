import 'dart:convert';

import 'package:heart/aws/aws.dart';
import 'package:heart/core/request.dart';
import 'package:heart/globals/config.dart';
import 'package:heart/globals/globals.dart';
import 'package:heart/middleware/aws.dart';
import 'package:heart/middleware/database.dart';
import 'package:heart/middleware/s3.dart';
import 'package:heart/models/errors.dart';
import 'package:heart/models/images.dart';
import 'package:heart_models/heart_models.dart';
import 'package:relic/relic.dart';

const _defaultAvatarMimeType = 'image/jpeg';

Future<Model> upsertAccount(final Request request) async {
  final body = await request.json();

  switch (body) {
    // cancellation of the account deletion schedule
    case {'action': 'undoAccountDeletion'}:
      final userId = request.userId;
      final scheduler = Scheduler(
        credentialsProvider: request.awsConfig.credentialsProvider,
        region: request.awsConfig.region,
      );
      await scheduler.deleteSchedule(
        name: 'account-deletion-$userId',
        groupName: request.config.scheduleGroup,
        throwIfMissing: false,
      );
      return request.profileService.undoAccountDeletion(userId: userId);

    // returns a presigned POST URL; the avatar lands at avatars/{userId}
    // via the /events handler after upload
    case {'action': 'uploadAvatar'}:
      final userId = request.userId;
      final mimeType = (body['mimeType'] as String?) ?? _defaultAvatarMimeType;
      if (!request.config.allowedMimeTypes.contains(mimeType)) {
        throw BadRequest(reason: 'Unsupported image type: $mimeType');
      }
      final destKey = 'avatars/$userId';
      final presigned = await request.imageStorageService.presignUpload(
        key: 'uploads/avatar-$userId',
        mimeType: mimeType,
        tags: [
          ('kind', 'avatar'),
          ('user-id', userId),
        ],
      );
      return PresignedUploadResponse(
        preSignedUrl: presigned,
        destinationUrl: request.config.cdnAssetUrl(destKey),
        key: destKey,
      );

    case {'action': 'removeAvatar'}:
      final userId = request.userId;
      await request.imageStorageService.deleteObject(key: 'avatars/$userId');
      return request.profileService.updateAvatarUrl(userId: userId, avatarUrl: null);

    // request from the user
    default:
      final user = request.user;
      final requestUser = User.fromJson(body);
      if (user.id != requestUser.id) {
        throw const Forbidden(reason: 'You can only modify your own profile');
      }
      return request.profileService.upsertProfile(requestUser);
  }
}

Future<NoContent> deleteAccount(final Request request) async {
  final userId = request.userId;
  final config = request.config;

  final scheduledAt = DateTime.now().toUtc().add(config.accountDeletionOffset);

  final scheduler = Scheduler(
    credentialsProvider: request.awsConfig.credentialsProvider,
    region: request.awsConfig.region,
  );

  final scheduleName = 'account-deletion-$userId';
  final createdArn = await scheduler.createSchedule(
    name: scheduleName,
    groupName: config.scheduleGroup,
    scheduleExpression: SchedulerApi.atExpression(scheduledAt),
    targetArn: config.eventsQueueArn,
    targetRoleArn: config.schedulerRoleArn,
    input: jsonEncode({
      'Event': 'AccountDeletion',
      'Payload': {'user_id': userId},
    }),
  );

  Future<Map> fallback() {
    return scheduler.getSchedule(name: scheduleName, groupName: config.scheduleGroup);
  }

  // 409 — the schedule already exists, fetch its ARN so we can still record it
  final scheduleArn = switch (createdArn) {
    String s => s,
    null => (await fallback())['Arn'],
  };

  await request.profileService.scheduleAccountDeletion(
    userId: userId,
    scheduleArn: scheduleArn,
    scheduledAt: scheduledAt,
  );

  throw const NoContent();
}
