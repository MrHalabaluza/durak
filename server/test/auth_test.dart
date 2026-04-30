import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart' as crypto;
import 'package:hashlib/hashlib.dart';
import 'package:test/test.dart';
import 'package:durak_server/db/database.dart';
import 'package:durak_server/db/user_dao.dart';
import 'package:durak_server/db/session_dao.dart';
import 'package:durak_server/auth/auth_service.dart';

String clientHash(String username, String password) {
  final input = utf8.encode('$username:$password');
  return crypto.sha256.convert(input).toString();
}

// AuthService with fast argon2id (little) for tests
class _FastAuthService {
  final UserDao _users;
  final SessionDao _sessions;
  _FastAuthService(this._users, this._sessions);

  static String _hashFast(String clientHashHex) {
    final salt = Uint8List.fromList(List.generate(16, (i) => i));
    return argon2id(
      Uint8List.fromList(clientHashHex.codeUnits),
      salt,
      security: Argon2Security.little,
    ).encoded();
  }

  static bool _verifyFast(String clientHashHex, String storedEncoded) =>
      argon2Verify(storedEncoded, Uint8List.fromList(clientHashHex.codeUnits));

  static String _validate(String input) {
    final trimmed = input.trim();
    final re = RegExp(r'^[\p{L}\p{N}_.\- ]{1,32}$', unicode: true);
    if (!re.hasMatch(trimmed)) {
      throw AuthException('invalid_username', 'Invalid username format');
    }
    return trimmed;
  }

  ({int userId, String username, String token, String? avatarPath}) register({
    required String username,
    required String clientPasswordHash,
  }) {
    final validated = _validate(username);
    if (_users.findByUsernameLower(validated.toLowerCase()) != null) {
      throw AuthException('username_taken', 'Username already in use');
    }
    final id = _users.create(
        username: validated, passwordHash: _hashFast(clientPasswordHash));
    final token = _sessions.create(id);
    return (userId: id, username: validated, token: token, avatarPath: null);
  }

  ({int userId, String username, String token, String? avatarPath}) login({
    required String username,
    required String clientPasswordHash,
  }) {
    final user = _users.findByUsernameLower(username.toLowerCase());
    if (user == null) throw AuthException('bad_credentials', 'Bad credentials');
    if (!_verifyFast(clientPasswordHash, user.passwordHash)) {
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

  dynamic resolveToken(String token) {
    final s = _sessions.find(token);
    if (s == null) return null;
    _sessions.touch(token);
    return _users.findById(s.userId);
  }
}

void main() {
  late AppDatabase appDb;
  late _FastAuthService auth;

  setUp(() {
    appDb = AppDatabase.open(':memory:');
    auth = _FastAuthService(UserDao(appDb.db), SessionDao(appDb.db));
  });
  tearDown(() => appDb.close());

  test('register ok', () {
    final res = auth.register(
      username: 'Вася',
      clientPasswordHash: clientHash('Вася', '123'),
    );
    expect(res.username, 'Вася');
    expect(res.token, isNotEmpty);
  });

  test('register повторно → username_taken', () {
    auth.register(
        username: 'Вася', clientPasswordHash: clientHash('Вася', '123'));
    expect(
      () => auth.register(
          username: 'Вася', clientPasswordHash: clientHash('Вася', '123')),
      throwsA(
          predicate((e) => e is AuthException && e.code == 'username_taken')),
    );
  });

  test('register с пробелом → trim, затем тот же → username_taken', () {
    auth.register(
        username: 'Вася ', clientPasswordHash: clientHash('Вася', '123'));
    expect(
      () => auth.register(
          username: 'вася', clientPasswordHash: clientHash('вася', '123')),
      throwsA(
          predicate((e) => e is AuthException && e.code == 'username_taken')),
    );
  });

  test('register !!! → invalid_username', () {
    expect(
      () => auth.register(
          username: '!!!', clientPasswordHash: clientHash('!!!', '123')),
      throwsA(predicate(
          (e) => e is AuthException && e.code == 'invalid_username')),
    );
  });

  test('login ok, токен не совпадает с регистрационным', () {
    final reg = auth.register(
        username: 'Вася', clientPasswordHash: clientHash('Вася', '123'));
    final log = auth.login(
        username: 'Вася', clientPasswordHash: clientHash('Вася', '123'));
    expect(log.token, isNotEmpty);
    expect(log.token, isNot(equals(reg.token)));
  });

  test('login неверный пароль → bad_credentials', () {
    auth.register(
        username: 'Вася', clientPasswordHash: clientHash('Вася', '123'));
    expect(
      () => auth.login(
          username: 'Вася', clientPasswordHash: clientHash('Вася', 'wrong')),
      throwsA(predicate(
          (e) => e is AuthException && e.code == 'bad_credentials')),
    );
  });

  test('resolveToken → user; после logout → null', () {
    final reg = auth.register(
        username: 'Вася', clientPasswordHash: clientHash('Вася', '123'));
    expect(auth.resolveToken(reg.token), isNotNull);
    auth.logout(reg.token);
    expect(auth.resolveToken(reg.token), isNull);
  });
}
