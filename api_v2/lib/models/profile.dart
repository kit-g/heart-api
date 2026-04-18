import 'package:heart/models/av.dart';
import 'package:heart_models/heart_models.dart';

abstract interface class Profile implements DynamoItem, Model {
  String get pk;

  String get sk;

  String? get name;

  String? get avatar;

  String get id;

  factory Profile.fromJson(Map json) {
    return _Profile(
      pk: json['PK'],
      sk: json['SK'],
      name: json['username'],
      avatar: json['avatar'],
    );
  }
}

class _Profile implements Profile {
  @override
  final String pk;
  @override
  final String id;
  @override
  final String sk;
  @override
  final String? name;
  @override
  final String? avatar;

  _Profile({
    required this.pk,
    required this.sk,
    required this.name,
    required this.avatar,
  }) : id = pk.split('#').last;

  @override
  Map<String, dynamic> toDynamoItem() {
    return {
      'PK': pk,
      'SK': sk,
      'name': name,
      'avatar': avatar,
    };
  }

  @override
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'avatar': avatar,
    };
  }
}
