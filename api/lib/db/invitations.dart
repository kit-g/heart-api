part of 'db.dart';

/// Pending links an inviter can hold at once: a guard, never expected to bind.
const _maxPendingInvitations = 50;

/// Declines in the last 30 days that stop an inviter making more. A busy coach
/// has many accepted, and one who is bothering people has many declined.
const _maxRecentDeclines = 20;

const _invitationLife = Duration(days: 7);

mixin _Invitations on _DatabaseBase implements InvitationService {
  @override
  Future<Invitation> createInvitation({
    required String inviterId,
    required String name,
    required ConnectionDomain domain,
    required String token,
  }) async {
    final rows = await _pool.execute(
      _createInvitation.toSql(),
      parameters: {
        'inviterId': inviterId,
        'name': name,
        'domain': domain.value,
        'tokenHash': TokenSecret.hash(token),
        'expiresAt': DateTime.now().toUtc().add(_invitationLife),
      },
    );
    final row = rows.first.toColumnMap();
    return switch (row) {
      {'entitled': false} => throw const Forbidden(
        code: 'coaching_beta',
        reason: 'coaching is open to testers for now',
      ),
      {'id': null} => throw const BadRequest(
        code: 'invitation_limit',
        reason: 'you have too many open or recently declined invitations',
      ),
      _ => Invitation.fromRow(row, token: token),
    };
  }

  @override
  Future<Page<Invitation>> getInvitations({required String inviterId, String? cursor, int limit = 30}) async {
    final rows = await _pool.execute(
      _listInvitations.toSql(),
      parameters: {'inviterId': inviterId, 'cursor': cursor, 'limit': limit + 1},
    );
    final invitations = rows.map((row) => Invitation.fromRow(row.toColumnMap())).toList();
    final hasMore = invitations.length > limit;
    return Page(items: hasMore ? invitations.sublist(0, limit) : invitations, hasMore: hasMore);
  }

  @override
  Future<void> cancelInvitation({required String inviterId, required String invitationId}) async {
    await _pool.execute(
      _cancelInvitation.toSql(),
      parameters: {'inviterId': inviterId, 'invitationId': invitationId},
    );
  }

  @override
  Future<Invitation> renewInvitation({
    required String inviterId,
    required String invitationId,
    required String token,
  }) async {
    final rows = await _pool.execute(
      _renewInvitation.toSql(),
      parameters: {
        'inviterId': inviterId,
        'invitationId': invitationId,
        'tokenHash': TokenSecret.hash(token),
        'expiresAt': DateTime.now().toUtc().add(_invitationLife),
      },
    );
    if (rows.isEmpty) throw NotFound(type: 'Invitation', id: invitationId);
    return Invitation.fromRow(rows.first.toColumnMap(), token: token);
  }

  @override
  Future<InvitationPreview?> previewInvitation({required String token}) async {
    final rows = await _pool.execute(_previewInvitation.toSql(), parameters: {'tokenHash': TokenSecret.hash(token)});
    return switch (rows.firstOrNull?.toColumnMap()) {
      null => null,
      final row => InvitationPreview(
        inviterName: row['username'] as String?,
        inviterAvatar: row['avatar_url'] as String?,
        good: row['good'] as bool,
      ),
    };
  }

  @override
  Future<Connection> acceptInvitation({
    required String userId,
    required String token,
    Set<ConnectionShare> shares = const {},
    String? email,
    String? name,
  }) async {
    final tokenHash = TokenSecret.hash(token);
    final row = await _pool.runTx((tx) async {
      await tx.execute(_lockInvitation.toSql(), parameters: {'tokenHash': tokenHash});
      final rows = await tx.execute(
        _acceptInvitation.toSql(),
        parameters: {
          'userId': userId,
          'tokenHash': tokenHash,
          'shares': [for (final share in shares) share.name],
          'email': email,
          'name': name,
        },
      );
      return rows.firstOrNull?.toColumnMap();
    });
    return switch (row) {
      null => throw const NotFound(type: 'Invitation', id: 'that link'),
      {'own': true} => throw const BadRequest(code: 'own_invitation', reason: 'this is your own invitation'),
      {'connection_id': final Object _} => Connection.fromRow(row),
      _ => throw const BadRequest(code: 'invitation_gone', reason: 'this invitation is no longer good'),
    };
  }

  @override
  Future<void> declineInvitation({required String userId, required String token, String? email, String? name}) async {
    final rows = await _pool.execute(
      _declineInvitation.toSql(),
      parameters: {'userId': userId, 'tokenHash': TokenSecret.hash(token), 'email': email, 'name': name},
    );
    if (rows.isEmpty) throw const NotFound(type: 'Invitation', id: 'that link');
  }

  @override
  Future<void> blockInviter({required String userId, required String token, String? email, String? name}) async {
    final rows = await _pool.execute(
      _blockInviter.toSql(),
      parameters: {'userId': userId, 'tokenHash': TokenSecret.hash(token), 'email': email, 'name': name},
    );
    if (rows.isEmpty) throw const NotFound(type: 'Invitation', id: 'that link');
  }

  @override
  Future<Page<BlockedPerson>> getBlocks({required String userId, String? cursor, int limit = 30}) async {
    final rows = await _pool.execute(
      _listBlocks.toSql(),
      parameters: {'userId': userId, 'cursor': cursor, 'limit': limit + 1},
    );
    final blocks = rows.map((row) => BlockedPerson.fromRow(row.toColumnMap())).toList();
    final hasMore = blocks.length > limit;
    return Page(items: hasMore ? blocks.sublist(0, limit) : blocks, hasMore: hasMore);
  }

  @override
  Future<void> liftBlock({required String userId, required String blockedId}) async {
    await _pool.execute(_liftBlock.toSql(), parameters: {'userId': userId, 'blockedId': blockedId});
  }
}
