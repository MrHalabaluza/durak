import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart' as crypto;
import 'package:hashlib/hashlib.dart';
import 'package:test/test.dart';
import 'package:durak_server/db/database.dart';
import 'package:durak_server/db/user_dao.dart';
import 'package:durak_server/db/session_dao.dart';
import 'package:durak_server/db/stats_dao.dart';
import 'package:durak_server/auth/auth_service.dart';
import 'package:durak_server/http/router.dart';
import 'package:durak_server/http/handlers_auth.dart';
import 'package:durak_server/http/handlers_me.dart';

// Fast argon2id for tests
String _hashFast(String hex) {
  final salt = Uint8List.fromList(List.generate(16, (i) => i));
  return argon2id(
    Uint8List.fromList(hex.codeUnits),
    salt,
    security: Argon2Security.little,
  ).encoded();
}

bool _verifyFast(String hex, String encoded) =>
    argon2Verify(encoded, Uint8List.fromList(hex.codeUnits));

// Full test auth service using fast hashing
class _FastAuthService extends AuthService {
  final UserDao _u;
  final SessionDao _s;

  _FastAuthService(this._u, this._s) : super(_u, _s);

  @override
  ({int userId, String username, String token, String? avatarPath}) register({
    required String username,
    required String clientPasswordHash,
  }) {
    final trimmed = username.trim();
    final re = RegExp(r'^[\p{L}\p{N}_.\- ]{1,32}$', unicode: true);
    if (!re.hasMatch(trimmed)) {
      throw AuthException('invalid_username', 'Invalid username format');
    }
    final lower = trimmed.toLowerCase();
    if (_u.findByUsernameLower(lower) != null) {
      throw AuthException('username_taken', 'Username already in use');
    }
    final stored = _hashFast(clientPasswordHash);
    final id = _u.create(username: trimmed, passwordHash: stored);
    final token = _s.create(id);
    return (userId: id, username: trimmed, token: token, avatarPath: null);
  }

  @override
  ({int userId, String username, String token, String? avatarPath}) login({
    required String username,
    required String clientPasswordHash,
  }) {
    final user = _u.findByUsernameLower(username.toLowerCase());
    if (user == null) throw AuthException('bad_credentials', 'Bad credentials');
    if (!_verifyFast(clientPasswordHash, user.passwordHash)) {
      throw AuthException('bad_credentials', 'Bad credentials');
    }
    final token = _s.create(user.id);
    return (
      userId: user.id,
      username: user.username,
      token: token,
      avatarPath: user.avatarPath
    );
  }
}

String clientHash(String username, String password) {
  final input = utf8.encode('$username:$password');
  return crypto.sha256.convert(input).toString();
}

Future<Map<String, dynamic>> httpPost(
  HttpClient client,
  String host,
  int port,
  String path,
  Map<String, dynamic> body, {
  String? token,
}) async {
  final req = await client.post(host, port, path);
  req.headers.contentType = ContentType.json;
  if (token != null) req.headers.set('Authorization', 'Bearer $token');
  req.write(jsonEncode(body));
  final resp = await req.close();
  final raw = await utf8.decoder.bind(resp).join();
  return {'status': resp.statusCode, 'body': raw.isEmpty ? null : jsonDecode(raw)};
}

Future<Map<String, dynamic>> httpGet(
  HttpClient client,
  String host,
  int port,
  String path, {
  String? token,
}) async {
  final req = await client.get(host, port, path);
  if (token != null) req.headers.set('Authorization', 'Bearer $token');
  final resp = await req.close();
  final raw = await utf8.decoder.bind(resp).join();
  return {'status': resp.statusCode, 'body': raw.isEmpty ? null : jsonDecode(raw)};
}

void main() {
  late AppDatabase appDb;
  late HttpServer server;
  late HttpClient client;
  late int port;

  setUp(() async {
    appDb = AppDatabase.open(':memory:');
    final userDao = UserDao(appDb.db);
    final sessionDao = SessionDao(appDb.db);
    final statsDao = StatsDao(appDb.db);
    final auth = _FastAuthService(userDao, sessionDao);

    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    port = server.port;

    final router = Router()
      ..add('POST', '/api/register', (r, _) => handleRegister(r, auth))
      ..add('POST', '/api/login', (r, _) => handleLogin(r, auth))
      ..add('POST', '/api/logout', (r, _) => handleLogout(r, auth))
      ..add('GET', '/api/me', (r, _) => handleGetMe(r, auth, statsDao));

    server.listen((req) async {
      if (await router.dispatch(req)) return;
      req.response
        ..statusCode = HttpStatus.notFound
        ..close();
    });

    client = HttpClient();
  });

  tearDown(() async {
    client.close();
    await server.close(force: true);
    appDb.close();
  });

  final host = '127.0.0.1';

  test('POST /api/register → 201, token непустой', () async {
    final res = await httpPost(client, host, port, '/api/register', {
      'username': 'Vasya',
      'password_hash': clientHash('Vasya', 'pass'),
    });
    expect(res['status'], 201);
    expect((res['body'] as Map)['token'], isNotEmpty);
  });

  test('POST /api/register повторно → 409', () async {
    await httpPost(client, host, port, '/api/register', {
      'username': 'Vasya',
      'password_hash': clientHash('Vasya', 'pass'),
    });
    final res = await httpPost(client, host, port, '/api/register', {
      'username': 'Vasya',
      'password_hash': clientHash('Vasya', 'pass'),
    });
    expect(res['status'], 409);
  });

  test('POST /api/login с верным паролем → 200, token', () async {
    await httpPost(client, host, port, '/api/register', {
      'username': 'Vasya',
      'password_hash': clientHash('Vasya', 'pass'),
    });
    final res = await httpPost(client, host, port, '/api/login', {
      'username': 'Vasya',
      'password_hash': clientHash('Vasya', 'pass'),
    });
    expect(res['status'], 200);
    expect((res['body'] as Map)['token'], isNotEmpty);
  });

  test('POST /api/login с неверным паролем → 401', () async {
    await httpPost(client, host, port, '/api/register', {
      'username': 'Vasya',
      'password_hash': clientHash('Vasya', 'pass'),
    });
    final res = await httpPost(client, host, port, '/api/login', {
      'username': 'Vasya',
      'password_hash': clientHash('Vasya', 'wrong'),
    });
    expect(res['status'], 401);
  });

  test('GET /api/me без токена → 401', () async {
    final res = await httpGet(client, host, port, '/api/me');
    expect(res['status'], 401);
  });

  test('GET /api/me с токеном → 200, корректный username', () async {
    final reg = await httpPost(client, host, port, '/api/register', {
      'username': 'Vasya',
      'password_hash': clientHash('Vasya', 'pass'),
    });
    final token = (reg['body'] as Map)['token'] as String;
    final res = await httpGet(client, host, port, '/api/me', token: token);
    expect(res['status'], 200);
    expect((res['body'] as Map)['user']['username'], 'Vasya');
  });

  test('POST /api/logout → 204; следующий GET /api/me → 401', () async {
    final reg = await httpPost(client, host, port, '/api/register', {
      'username': 'Vasya',
      'password_hash': clientHash('Vasya', 'pass'),
    });
    final token = (reg['body'] as Map)['token'] as String;

    final logout = await httpPost(
        client, host, port, '/api/logout', {},
        token: token);
    expect(logout['status'], 204);

    final me = await httpGet(client, host, port, '/api/me', token: token);
    expect(me['status'], 401);
  });
}
