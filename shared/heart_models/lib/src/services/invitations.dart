import '../models/connections.dart';
import '../models/invitation.dart';
import '../models/pagination.dart';

abstract interface class InvitationService {
  /// A new link from [inviterId], for a person they call [name]. Throws when the
  /// account can't invite yet, or has reached a limit. The answer carries the
  /// link's secret, the only time it is readable.
  Future<Invitation> createInvitation({
    required String inviterId,
    required String name,
    required ConnectionDomain domain,
    required String token,
  });

  /// [inviterId]'s links, newest first, however they ended.
  Future<Page<Invitation>> getInvitations({required String inviterId, String? cursor, int limit = 30});

  /// Withdraws a link. Withdrawing what isn't there or has already been answered
  /// is not an error.
  Future<void> cancelInvitation({required String inviterId, required String invitationId});

  /// A new secret and a new expiry for a link nobody has accepted.
  Future<Invitation> renewInvitation({required String inviterId, required String invitationId, required String token});

  /// What a link says to anyone who opens it. `null` if there is no such link.
  Future<InvitationPreview?> previewInvitation({required String token});

  /// Starts the relationship, opening [shares] to the inviter. Accepting twice
  /// is a no-op, and answers the same connection: `connected` says whether this
  /// call is the one that made it. Throws when the link is no longer good. Someone
  /// who only just made an account on the web gets a profile from [email] and [name].
  Future<({Connection connection, bool connected})> acceptInvitation({
    required String userId,
    required String token,
    Set<ConnectionShare> shares = const {},
    String? email,
    String? name,
  });

  /// Says no. A person can still change their mind while the link is good.
  Future<void> declineInvitation({required String userId, required String token, String? email, String? name});

  /// Says no and blocks the person who made the link.
  Future<void> blockInviter({required String userId, required String token, String? email, String? name});

  /// Who [userId] has blocked.
  Future<Page<BlockedPerson>> getBlocks({required String userId, String? cursor, int limit = 30});

  /// Lifts [userId]'s block on [blockedId], which ends a row it held at `blocked`.
  Future<void> liftBlock({required String userId, required String blockedId});
}
