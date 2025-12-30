import 'package:heart_models/heart_models.dart';

class VersionInfo implements Model {
  final String commit;
  final String deployedAt;

  const VersionInfo({required this.commit, required this.deployedAt});

  @override
  Map<String, dynamic> toMap() => {
    'commit': commit,
    'deployedAt': deployedAt,
  };
}
