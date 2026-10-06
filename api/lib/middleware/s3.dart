import 'package:relic/relic.dart';

import '../models/exercises.dart';
import '../models/exports.dart';
import '../models/images.dart';

final _exercisesProperty = ContextProperty<ExerciseService>('ExerciseService');
final _imageStorageProperty = ContextProperty<ApiImageStorageService>('ApiImageStorageService');
final _exportStorageProperty = ContextProperty<ExportStorage>('ExportStorage');

Middleware exercisesDb({required ExerciseService db}) {
  return (Handler next) {
    return (request) {
      _exercisesProperty[request] = db;
      return next(request);
    };
  };
}

Middleware imageStorageDb({required ApiImageStorageService db}) {
  return (Handler next) {
    return (request) {
      _imageStorageProperty[request] = db;
      return next(request);
    };
  };
}

Middleware exportStorage({required ExportStorage storage}) {
  return (Handler next) {
    return (request) {
      _exportStorageProperty[request] = storage;
      return next(request);
    };
  };
}

extension StorageService on Request {
  ExerciseService get exerciseService => _exercisesProperty.get(this);

  set exerciseService(ExerciseService v) => _exercisesProperty[this] = v;

  ApiImageStorageService get imageStorageService => _imageStorageProperty.get(this);

  set imageStorageService(ApiImageStorageService v) => _imageStorageProperty[this] = v;

  ExportStorage get exportStorage => _exportStorageProperty.get(this);

  set exportStorage(ExportStorage v) => _exportStorageProperty[this] = v;
}
