import 'dart:convert';

import 'package:heart/globals/config.dart';
import 'package:heart/globals/globals.dart';
import 'package:heart/inputs/inputs.dart';
import 'package:heart/middleware/apple.dart';
import 'package:heart/middleware/aws.dart';
import 'package:heart/middleware/database.dart';
import 'package:heart/middleware/s3.dart';
import 'package:heart/models/errors.dart';
import 'package:heart/models/images.dart';
import 'package:heart_aws/heart_aws.dart';
import 'package:heart_models/heart_models.dart';
import 'package:relic/relic.dart';

Future<Model> upsertAccount(Request request) async {
  final input = await AccountUpsertIn.fromRequest(request);

  switch (input) {
    case ScheduleAccountDeletionIn(:final appleGrant):
      return _scheduleAccountDeletion(request, appleGrant);

    // cancellation of the account deletion schedule
    case UndoAccountDeletionIn():
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
    case UploadAvatarIn(:final mimeType):
      final userId = request.userId;
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

    case RemoveAvatarIn():
      final userId = request.userId;
      await request.imageStorageService.deleteObject(key: 'avatars/$userId');
      return request.profileService.updateAvatarUrl(userId: userId, avatarUrl: null);

    // request from the user
    case ProfileUpsertIn(:final user):
      if (request.user.id != user.id) {
        throw const Forbidden(reason: 'You can only modify your own profile');
      }
      return request.profileService.upsertProfile(user);
  }
}

/// What the account holds server-side, one collection at a time.
///
/// The app's export runs off its local mirror, so before it writes a file it
/// needs to know the mirror is whole — this is what it compares against.
Future<AccountSummary> getAccountSummary(Request request) {
  return request.profileService.getAccountSummary(request.userId);
}

/// Sets the account's deletion running: an Apple grant exchanged while the user
/// is still here to authorize it, a one-shot schedule, and both recorded on the
/// profile in a single write.
///
/// Returns the updated profile rather than a bare 204, so the caller learns the
/// deadline it is about to show from the same round trip that set it.
Future<User> _scheduleAccountDeletion(Request request, AppleDeletionGrant? grant) async {
  final userId = request.userId;
  final config = request.config;

  // Spent here rather than when the schedule fires, because Apple's
  // authorization code expires within minutes and the deletion is days away.
  // A failed exchange leaves nothing to revoke and is logged as such; it is
  // never the reason a user cannot delete their account.
  final appleGrant = switch (grant) {
    AppleDeletionGrant(:final authorizationCode, :final clientId) => switch (await request.apple
        .exchangeAuthorizationCode(code: authorizationCode, clientId: clientId)) {
      final String refreshToken => (refreshToken: refreshToken, clientId: clientId),
      null => null,
    },
    null => null,
  };

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

  return request.profileService.scheduleAccountDeletion(
    userId: userId,
    scheduleArn: scheduleArn,
    scheduledAt: scheduledAt,
    appleGrant: appleGrant,
  );
}
