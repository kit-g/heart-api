import '../models/push.dart';

/// Who a push would reach, and how they want it.
typedef PushAudience = ({
  /// A block stands between the person and whoever the push is about.
  bool blocked,

  /// What they said for this relationship, then for this topic. Null if nothing.
  String? forPerson,
  String? forTopic,
  List<({String token, String locale})> devices,
});

abstract interface class PushService {
  /// Everything [userId] has said about any topic.
  Future<List<PushPreference>> getPushPreferences({required String userId});

  Future<void> setPushPreference({
    required String userId,
    required String topic,
    required String delivery,
    String? connectionId,
  });

  /// Goes back to what the rest of the topic does, or to its default.
  Future<void> clearPushPreference({required String userId, required String topic, String? connectionId});

  Future<PushAudience> getPushAudience({
    required String userId,
    required String topic,
    String? connectionId,
    String? actorId,
  });

  /// Owes [userId] a push of [topic] on their next evening, once.
  Future<void> queueDigest({required String userId, required String topic});

  /// The digests owed to people for whom it's now [localHour], removed from what
  /// is owed. One person's evening comes from the device they last used.
  Future<List<({String userId, String topic})>> claimDueDigests({required int localHour});
}
