import '../db/models.dart';
import '../db/user_dao.dart';
import '../db/session_dao.dart';
import 'password.dart';

class AuthService {
  final UserDao _users;
  final SessionDao _sessions;
  AuthService(this._users, this._sessions);

  ({int userId, String username, String token, String? avatarPath}) register({
    required String username,
    required String clientPasswordHash,
  }) {
    final usernameValidated = _validateUsername(username);
    final lower = usernameValidated.toLowerCase();
    if (_users.findByUsernameLower(lower) != null) {
      throw AuthException('username_taken', 'Username already in use');
    }
    final stored = PasswordHasher.hash(clientPasswordHash);
    final id = _users.create(username: usernameValidated, passwordHash: stored);
    final token = _sessions.create(id);
    return (
      userId: id,
      username: usernameValidated,
      token: token,
      avatarPath: null
    );
  }

  ({int userId, String username, String token, String? avatarPath}) login({
    required String username,
    required String clientPasswordHash,
  }) {
    final user = _users.findByUsernameLower(username.toLowerCase());
    if (user == null) throw AuthException('bad_credentials', 'Bad credentials');
    if (!PasswordHasher.verify(clientPasswordHash, user.passwordHash)) {
      throw AuthException('bad_credentials', 'Bad credentials');
    }
    final token = _sessions.create(user.id);
    return (
      userId: user.id,
      username: user.username,
      token: token,
      avatarPath: user.avatarPath
    );
  }

  void logout(String token) => _sessions.delete(token);

  UserRow? resolveToken(String token) {
    final s = _sessions.find(token);
    if (s == null) return null;
    _sessions.touch(token);
    return _users.findById(s.userId);
  }

  static String _validateUsername(String input) {
    final trimmed = input.trim();
    final re = RegExp(r'^[\p{L}\p{N}_.\- ]{1,32}$', unicode: true);
    if (!re.hasMatch(trimmed)) {
      throw AuthException('invalid_username', 'Invalid username format');
    }
    return trimmed;
  }
}

class AuthException implements Exception {
  final String code;
  final String message;
  AuthException(this.code, this.message);
}
