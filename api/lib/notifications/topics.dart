import 'package:heart_models/heart_models.dart';

/// Every push Heart can send. A new one is an entry here and its copy in
/// `templates.dart`: no migration and no app release.
enum PushTopic {
  commentCreated(
    key: 'comment.created',
    group: 'comments',
    fallback: instant,
    options: [instant, off],
    channel: 'comments',
  ),
  reactionCreated(
    key: 'reaction.created',
    group: 'reactions',
    fallback: instant,
    options: [instant, off],
    channel: 'reactions',
  ),
  coachingMessage(
    key: 'coaching.message',
    group: 'coaching',
    fallback: instant,
    options: [instant, off],
    channel: 'messages',
    perPersonAs: [.coach, .student, .peer],
  ),
  coachingWorkoutDigest(
    key: 'coaching.workout_digest',
    group: 'coaching',
    fallback: daily,
    options: [daily, off],
    channel: 'coaching',
    collapses: true,
    perPersonAs: [.coach],
  ),
  invitationAccepted(
    key: 'coaching.invitation_accepted',
    group: 'coaching',
    fallback: instant,
    options: [instant, off],
    channel: 'coaching',
  ),
  programReceived(
    key: 'coaching.program_received',
    group: 'coaching',
    fallback: instant,
    options: [instant, off],
    channel: 'coaching',
    perPersonAs: [.student],
  ),

  /// Wakes the app to fetch what changed. It says nothing, so nothing to choose.
  programChanged(key: 'coaching.program_changed', group: 'coaching', silent: true),

  /// Wakes the app to drop a conversation someone deleted for both sides.
  threadCleared(key: 'coaching.thread_cleared', group: 'coaching', silent: true),

  /// Wakes the app to look at the other person's devices.
  devicesChanged(key: 'security.devices_changed', group: 'security', silent: true),

  /// Wakes the app to read its key queue: something arrived for one of its devices.
  /// Each says the same, so one waiting for an offline phone stands for them all.
  queueWaiting(key: 'security.queue_waiting', group: 'security', silent: true, collapses: true),
  ;

  static const instant = 'instant';
  static const daily = 'daily';
  static const off = 'off';

  final String key;
  final String group;
  final String fallback;
  final List<String> options;
  final bool silent;
  final String? channel;

  /// Whether a newer push of this topic replaces one still waiting for an
  /// offline device. Only for a topic whose pushes all say the same thing: two
  /// messages, or two people's device changes, are two things to hear about.
  final bool collapses;

  /// The reader's roles in a connection for which a choice about one person reaches
  /// a push: the side this topic is sent to, with that person's connection. Empty
  /// for a topic sent without one, and for `coaching.invitation_accepted`, which
  /// goes once, before anyone could choose for that person.
  final List<ConnectionRole> perPersonAs;

  new({
    required this.key,
    required this.group,
    this.fallback = instant,
    this.options = const [],
    this.silent = false,
    this.channel,
    this.collapses = false,
    this.perPersonAs = const [],
  });

  static PushTopic? of(String key) {
    for (final topic in values) {
      if (topic.key == key) return topic;
    }
    return null;
  }

  /// What a person can change: a silent push isn't theirs to choose.
  static Iterable<PushTopic> get settable => values.where((topic) => !topic.silent);

  /// What [forPerson] and [forTopic] make of this topic. A word this topic doesn't
  /// offer, such as one a later version stored, falls back to the default.
  String deliveryFor({String? forPerson, String? forTopic}) {
    for (final said in [forPerson, forTopic]) {
      if (said != null && options.contains(said)) return said;
    }
    return fallback;
  }
}
