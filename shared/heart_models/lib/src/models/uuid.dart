import 'package:uuid/v7.dart';

var _uuid = const UuidV7();

String uuidV7() => _uuid.generate();

abstract mixin class HasUuid {
  final String uuid = const UuidV7().generate();
}
