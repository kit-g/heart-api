import 'package:relic/relic.dart';

import '../models/exercises.dart';
import '../models/exports.dart';
import '../models/images.dart';
import '../models/imports.dart';
import '../models/lens.dart';
import '../models/library.dart';

final _exercisesProperty = ContextProperty<ExerciseService>('ExerciseService');
final _imageStorageProperty = ContextProperty<ApiImageStorageService>('ApiImageStorageService');
final _exportStorageProperty = ContextProperty<ExportStorage>('ExportStorage');
final _importStorageProperty = ContextProperty<ImportStorage>('ImportStorage');
final _programLibraryProperty = ContextProperty<ProgramLibrary>('ProgramLibrary');
final _balancePairsProperty = ContextProperty<BalancePairs>('BalancePairs');

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

Middleware importStorage({required ImportStorage storage}) {
  return (Handler next) {
    return (request) {
      _importStorageProperty[request] = storage;
      return next(request);
    };
  };
}

Middleware programLibrary({required ProgramLibrary library}) {
  return (Handler next) {
    return (request) {
      _programLibraryProperty[request] = library;
      return next(request);
    };
  };
}

Middleware balancePairs({required BalancePairs pairs}) {
  return (Handler next) {
    return (request) {
      _balancePairsProperty[request] = pairs;
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

  ImportStorage get importStorage => _importStorageProperty.get(this);

  set importStorage(ImportStorage v) => _importStorageProperty[this] = v;

  ProgramLibrary get programLibrary => _programLibraryProperty.get(this);

  set programLibrary(ProgramLibrary v) => _programLibraryProperty[this] = v;

  BalancePairs get balancePairs => _balancePairsProperty.get(this);

  set balancePairs(BalancePairs v) => _balancePairsProperty[this] = v;
}
