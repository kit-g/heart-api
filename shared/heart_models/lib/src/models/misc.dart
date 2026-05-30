import 'dart:async';

abstract interface class SignOutStateSentry {
  FutureOr<void> onSignOut();
}

abstract interface class Searchable {
  bool contains(String query);
}

abstract interface class Model {
  Map<String, dynamic> toMap();
}

abstract interface class Storable {
  Map<String, dynamic> toRow();
}

enum MeasurementUnit {
  imperial('imperial'),
  metric('metric');

  final String name;

  const MeasurementUnit(this.name);

  factory MeasurementUnit.fromString(String v) {
    return switch (v) {
      'imperial' => .imperial,
      'metric' => .metric,
      _ => throw ArgumentError(v),
    };
  }
}

extension Units on num {
  double get asPounds => this * 2.20462262185;

  double get asKilograms => this * 0.45359237;

  double get asMiles => this * 0.62137119224;

  double get asKilometers => this * 1.609344;
}

abstract interface class HeaderAuthenticatedService {
  void authenticate(Map<String, String> headers);

  void reauthenticate(String sessionToken);

  bool get isAuthenticated;
}

abstract interface class FileUploadService {
  Future<bool> uploadFile(
    ({String url, Map<String, String> fields}) cred,
    (String field, List<int> value, {String? filename, String? contentType}) file, {
    final void Function(int bytes, int totalBytes)? onProgress,
  });
}

typedef PreSignedUrl = ({String url, Map<String, String> fields});
