import 'package:heart_models/heart_models.dart';

abstract interface class ApiProfileService {
  Future<void> upsertProfile(User user);
}

abstract interface class Profile implements Model {
  String? get name;

  String? get avatar;

  String get id;

  factory Profile({
    required String id,
    required String name,
    required String avatar,
  }) = _Profile.new;

  factory Profile.fromJson(Map json) {
    return _Profile(
      id: json['id'],
      name: json['username'],
      avatar: json['avatar'],
    );
  }
}

class _Profile implements Profile {
  @override
  final String id;
  @override
  final String? name;
  @override
  final String? avatar;

  const _Profile({
    required this.id,
    required this.name,
    required this.avatar,
  });

  @override
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'avatar': avatar,
    };
  }
}
