import 'package:relic/relic.dart';

import '../models/exercises.dart';

final _property = ContextProperty<ExerciseService>('ExerciseService');

Middleware exercisesDb({required ExerciseService db}) {
  return (final Handler next) {
    return (final request) {
      _property[request] = db;
      return next(request);
    };
  };
}

extension StorageService on Request {
  ExerciseService get exerciseService => _property.get(this);

  set exerciseService(ExerciseService v) => _property[this] = v;
}
