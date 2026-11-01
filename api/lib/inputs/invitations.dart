part of 'inputs.dart';

/// `POST /invitations` — `{name, domain?}`. `name` is what the inviter calls the
/// person it is for.
class InvitationCreateIn {
  final String name;
  final ConnectionDomain domain;

  /// A library program to start with, sent on acceptance.
  final String? programId;

  const new _({required this.name, required this.domain, this.programId});

  static Future<InvitationCreateIn> fromRequest(Request req) async {
    final json = await req.json();
    final name = json.string('name').trim();
    if (name.isEmpty || name.length > 100) {
      throw const BadRequest(reason: 'name must be between 1 and 100 characters');
    }
    return InvitationCreateIn._(
      name: name,
      domain: switch (json['domain']) {
        null => ConnectionDomain.fitness,
        _ => json.parsed('domain', ConnectionDomain.fromString),
      },
      programId: switch (json['programId']) {
        null => null,
        final String id when isUuidV7(id) => id,
        _ => throw const BadRequest(reason: 'programId must be a program\'s id'),
      },
    );
  }
}

/// `POST /invitation-links/:token/accept` — optionally `{shares: [...]}`.
class InvitationAcceptIn {
  final Set<ConnectionShare> shares;

  const new _(this.shares);

  static Future<InvitationAcceptIn> fromRequest(Request req) async {
    final json = await req.json();
    return InvitationAcceptIn._(
      switch (json['shares']) {
        null => const {},
        final List shares => ConnectionSharesIn.parse(shares),
        _ => throw const BadRequest(reason: 'shares must be a list'),
      },
    );
  }
}
