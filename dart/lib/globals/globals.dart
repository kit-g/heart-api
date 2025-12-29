import 'package:heart_models/models.dart';
import 'package:relic/relic.dart';

final _userProperty = ContextProperty<User>('RequestUser');

extension RequestUser on Request {
  User get user => _userProperty.get(this);

  String get userId => user.id;

  set user(User u) => _userProperty[this] = u;
}
