part of 'inputs.dart';

/// `POST /connections` — `{targetId, role, domain}`.
///
/// [role] is the role the caller is claiming **for themselves**; the reciprocal
/// is what gets written to the other side of the row.
class ConnectionCreateIn {
  final String targetId;
  final ConnectionRole role;
  final ConnectionDomain domain;

  const new _({
    required this.targetId,
    required this.role,
    required this.domain,
  });

  static Future<ConnectionCreateIn> fromRequest(Request req) async {
    final json = await req.json();
    final targetId = json.string('targetId');

    // Mirrors connections_no_self_check, which would otherwise surface as a 500.
    if (targetId == req.userId) {
      throw const BadRequest(reason: 'you cannot connect to yourself');
    }

    final role = json.parsed('role', ConnectionRole.fromString);

    // A coach's narrower view rests on what the student said when accepting, so
    // that relationship only starts from an invitation.
    if (role != .peer) {
      throw const BadRequest(code: 'invitation_required', reason: 'a coaching connection starts with an invitation');
    }

    return ConnectionCreateIn._(
      targetId: targetId,
      role: role,
      domain: json.parsed('domain', ConnectionDomain.fromString),
    );
  }
}

/// `PUT /connections/:connectionId` — `{status}`.
class ConnectionStatusIn {
  final ConnectionStatus status;

  const new _(this.status);

  static Future<ConnectionStatusIn> fromRequest(Request req) async {
    final json = await req.json();
    return ConnectionStatusIn._(json.parsed('status', ConnectionStatus.fromString));
  }
}

/// `PUT /connections/:connectionId/shares` — `{shares: [...]}`, the whole list.
class ConnectionSharesIn {
  final Set<ConnectionShare> shares;

  const new _(this.shares);

  static Future<ConnectionSharesIn> fromRequest(Request req) async {
    final json = await req.json();
    return switch (json['shares']) {
      final List shares => ConnectionSharesIn._(_parse(shares)),
      _ => throw const BadRequest(reason: 'shares must be a list'),
    };
  }

  static Set<ConnectionShare> _parse(List shares) {
    try {
      return {for (final share in shares) ConnectionShare.fromString('$share')};
    } on ArgumentError catch (e) {
      throw BadRequest(reason: '${e.message}: ${e.invalidValue}');
    }
  }
}

/// `GET /connections?role=` — filters on the **caller's own** role, so
/// `?role=COACH` lists the people they coach, not their coaches.
class ConnectionListQuery {
  final ConnectionRole? role;

  const new _(this.role);

  static ConnectionListQuery fromRequest(Request req) {
    final query = req.url.queryParameters;
    return ConnectionListQuery._(
      switch (query.stringOrNull('role')) {
        null => null,
        _ => query.parsed('role', ConnectionRole.fromString),
      },
    );
  }
}

/// The path segment of `PUT`/`DELETE /connections/:connectionId`.
///
/// The id is synthetic and viewer-relative — `<targetId>|<ROLE>|<DOMAIN>`, which
/// [Connection.fromId] parses back into the three things needed to address the
/// row from the caller's side.
class ConnectionRef {
  final String targetId;
  final ConnectionRole role;
  final ConnectionDomain domain;

  const new _({required this.targetId, required this.role, required this.domain});

  static ConnectionRef parse(String connectionId) {
    try {
      final (targetId, role, domain) = Connection.fromId(connectionId);
      return ConnectionRef._(targetId: targetId, role: role, domain: domain);
    } on ArgumentError catch (e) {
      throw BadRequest(reason: e.message.toString());
    }
  }
}
