part of 'aws.dart';

extension on int {
  String pad([int digits = 2]) {
    return toString().padLeft(digits, '0');
  }
}
