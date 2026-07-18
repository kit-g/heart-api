import 'package:heart_models/heart_models.dart';

abstract interface class GoalsResponse implements Model {
  Iterable<Goal> get goals;

  factory GoalsResponse({required final Iterable<Goal> goals}) = _GoalsResponse.new;
}

class _GoalsResponse implements GoalsResponse {
  @override
  final Iterable<Goal> goals;

  _GoalsResponse({required this.goals});

  @override
  Map<String, dynamic> toMap() {
    return {
      'goals': goals.map((each) => each.toMap()).toList(),
    };
  }
}
