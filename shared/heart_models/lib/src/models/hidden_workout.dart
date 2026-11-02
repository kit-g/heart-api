import 'misc.dart';

/// A workout its owner hid from their connections.
abstract interface class HiddenWorkout implements Model {
  String get id;

  DateTime get at;

  factory({required String id, required DateTime at}) = _HiddenWorkout.new;

  factory fromRow(Map row) => HiddenWorkout(id: row['id'].toString(), at: row['hidden_at'] as DateTime);

  factory fromJson(Map json) => HiddenWorkout(id: json['id'] as String, at: DateTime.parse(json['at'] as String));
}

class _HiddenWorkout implements HiddenWorkout {
  @override
  final String id;
  @override
  final DateTime at;

  const new({required this.id, required this.at});

  @override
  Map<String, dynamic> toMap() => {'id': id, 'at': at.toIso8601String()};
}
