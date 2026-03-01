library;

import 'dart:convert';

import 'package:aws_client/s3_2006_03_01.dart';

import '../models/exercises.dart';

part 'exercises.dart';

abstract class _StorageBase {
  S3 get client;

  String get exerciseBucket;

  const _StorageBase();
}

class Storage extends _StorageBase with _Exercises implements ExerciseService {
  @override
  final S3 client;
  @override
  final String exerciseBucket;

  const Storage({
    required this.client,
    required this.exerciseBucket,
  });
}
