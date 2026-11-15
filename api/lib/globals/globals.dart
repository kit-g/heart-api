import 'package:heart_models/heart_models.dart';
import 'package:relic/relic.dart';

final _userProperty = ContextProperty<User>('RequestUser');
final _scopesProperty = ContextProperty<List<String>>('TokenScopes');

extension RequestUser on Request {
  User get user => _userProperty.get(this);

  String get userId => user.id;

  set user(User u) => _userProperty[this] = u;

  /// What the request's token may do, on a surface a token authenticates; null
  /// on the app's, which a session authenticates.
  List<String>? get scopes => _scopesProperty[this];

  set scopes(List<String>? scopes) => _scopesProperty[this] = scopes;
}
