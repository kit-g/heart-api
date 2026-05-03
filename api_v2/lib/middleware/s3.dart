import 'package:relic/relic.dart';

import '../models/exercises.dart';
import '../models/images.dart';

final _exercisesProperty = ContextProperty<ExerciseService>('ExerciseService');
final _imageStorageProperty = ContextProperty<ApiImageStorageService>('ApiImageStorageService');

Middleware exercisesDb({required ExerciseService db}) {
  return (final Handler next) {
    return (final request) {
      _exercisesProperty[request] = db;
      return next(request);
    };
  };
}

Middleware imageStorageDb({required ApiImageStorageService db}) {
  return (final Handler next) {
    return (final request) {
      _imageStorageProperty[request] = db;
      return next(request);
    };
  };
}

extension StorageService on Request {
  ExerciseService get exerciseService => _exercisesProperty.get(this);

  set exerciseService(ExerciseService v) => _exercisesProperty[this] = v;

  ApiImageStorageService get imageStorageService => _imageStorageProperty.get(this);

  set imageStorageService(ApiImageStorageService v) => _imageStorageProperty[this] = v;
}
