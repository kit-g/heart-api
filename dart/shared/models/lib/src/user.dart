import 'model.dart' show Model;

abstract interface class User implements Model {
  String get id;

  String? get email;

  bool? get emailVerified;

  factory User({
    required String id,
    String? email,
    bool? emailVerified,
  }) = _User.new;
}

class _User implements User {
  @override
  final String id;
  @override
  final String? email;
  @override
  final bool? emailVerified;

  const _User({
    required this.id,
    this.email,
    this.emailVerified,
  });

  @override
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'email': email,
    };
  }

  @override
  String toString() {
    return 'User #$id at $email';
  }
}
