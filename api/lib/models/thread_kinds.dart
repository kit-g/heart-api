/// What a thread accepts, and how each kind behaves: whether it pushes the other
/// person, and whether it counts as something to read. A reaction to a message is
/// sealed like the message, but says nothing worth a push or an unread mark.
///
/// Sealing something else for the other person (a skip's reason, say) would be
/// one more entry here, and that's a policy decision: see
/// docs/2026-11-01.coaching.md, *Messages*.
const threadItemKinds = <String, ({bool pushes, bool unread})>{
  'message': (pushes: true, unread: true),
  'reaction': (pushes: false, unread: false),
};

/// The kinds that don't count as unread, as the inbox's query takes them.
final quietThreadKinds = [
  for (final MapEntry(:key, :value) in threadItemKinds.entries)
    if (!value.unread) key,
];
