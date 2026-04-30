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
import 'package:durak_server/http/handlers_users.dart';
import 'package:durak_server/http/handlers_stats.dart';
import 'package:durak_server/http/handlers_avatar.dart';

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
  final bytes = await resp.fold<List<int>>([], (a, b) => a..addAll(b));
  String? text;
  try {
    text = utf8.decode(bytes);
  } catch (_) {}
  dynamic body;
  if (text != null && text.isNotEmpty) {
    try {
      body = jsonDecode(text);
    } catch (_) {
      body = text;
    }
  }
  return {'status': resp.statusCode, 'body': body};
}

Uint8List _buildMultipart(
    String boundary, String fieldName, String filename, Uint8List fileBytes) {
  final buf = <int>[];
  void s(String v) => buf.addAll(v.codeUnits);
  s('--$boundary\r\n');
  s('Content-Disposition: form-data; name="$fieldName"; filename="$filename"\r\n');
  s('Content-Type: application/octet-stream\r\n');
  s('\r\n');
  buf.addAll(fileBytes);
  s('\r\n--$boundary--\r\n');
  return Uint8List.fromList(buf);
}

Future<Map<String, dynamic>> httpPostMultipart(
  HttpClient client,
  String host,
  int port,
  String path,
  Uint8List body,
  String boundary, {
  String? token,
}) async {
  final req = await client.post(host, port, path);
  req.headers.set(
      'Content-Type', 'multipart/form-data; boundary=$boundary');
  if (token != null) req.headers.set('Authorization', 'Bearer $token');
  req.add(body);
  final resp = await req.close();
  final raw = await utf8.decoder.bind(resp).join();
  return {
    'status': resp.statusCode,
    'body': raw.isEmpty ? null : jsonDecode(raw),
  };
}

void main() {
  late AppDatabase appDb;
  late HttpServer server;
  late HttpClient client;
  late int port;
  late Directory tempAvatarsDir;

  setUp(() async {
    appDb = AppDatabase.open(':memory:');
    final userDao = UserDao(appDb.db);
    final sessionDao = SessionDao(appDb.db);
    final statsDao = StatsDao(appDb.db);
    final auth = _FastAuthService(userDao, sessionDao);
    tempAvatarsDir =
        Directory.systemTemp.createTempSync('durak_avatars_test_');

    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    port = server.port;

    final avatarsDir = tempAvatarsDir.path;
    final router = Router()
      ..add('POST', '/api/register', (r, _) => handleRegister(r, auth))
      ..add('POST', '/api/login', (r, _) => handleLogin(r, auth))
      ..add('POST', '/api/logout', (r, _) => handleLogout(r, auth))
      ..add('GET', '/api/me', (r, _) => handleGetMe(r, auth, statsDao))
      ..add('GET', '/api/users/:id', (r, p) => handleGetUser(r, p, userDao, statsDao))
      ..add('GET', '/api/leaderboard', (r, _) => handleLeaderboard(r, statsDao))
      ..add('GET', '/api/server-stats', (r, _) => handleServerStats(r, statsDao, 0))
      ..add('POST', '/api/me/avatar', (r, _) => handleUploadAvatar(r, auth, userDao, avatarsDir))
      ..add('GET', '/avatars/:filename', (r, p) => handleGetAvatar(r, p, avatarsDir));

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
    tempAvatarsDir.deleteSync(recursive: true);
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

  // --- Шаг 6 ---

  test('GET /api/users/:id → 200 с правильным username', () async {
    final reg = await httpPost(client, host, port, '/api/register', {
      'username': 'Alice',
      'password_hash': clientHash('Alice', 'pass'),
    });
    final userId = (reg['body'] as Map)['user']['id'] as int;
    final res = await httpGet(client, host, port, '/api/users/$userId');
    expect(res['status'], 200);
    expect((res['body'] as Map)['user']['username'], 'Alice');
  });

  test('GET /api/users/9999 → 404', () async {
    final res = await httpGet(client, host, port, '/api/users/9999');
    expect(res['status'], 404);
  });

  test('GET /api/leaderboard?sort=wins → порядок по победам', () async {
    // Регистрируем трёх пользователей
    final regA = await httpPost(client, host, port, '/api/register',
        {'username': 'A', 'password_hash': clientHash('A', 'p')});
    final regB = await httpPost(client, host, port, '/api/register',
        {'username': 'B', 'password_hash': clientHash('B', 'p')});
    await httpPost(client, host, port, '/api/register',
        {'username': 'C', 'password_hash': clientHash('C', 'p')});

    final aId = (regA['body'] as Map)['user']['id'] as int;
    final bId = (regB['body'] as Map)['user']['id'] as int;

    // Запись двух партий через DAO напрямую
    final statsDao2 = StatsDao(appDb.db);
    statsDao2.recordGame(
      roomId: 'R1',
      startedAt: DateTime.now(),
      finishedAt: DateTime.now(),
      participantUserIds: [aId, bId],
      loserUserId: bId,
    );
    statsDao2.recordGame(
      roomId: 'R2',
      startedAt: DateTime.now(),
      finishedAt: DateTime.now(),
      participantUserIds: [aId, bId],
      loserUserId: bId,
    );

    final res = await httpGet(
        client, host, port, '/api/leaderboard?sort=wins&order=desc');
    expect(res['status'], 200);
    final items = (res['body'] as Map)['items'] as List;
    // A (2 победы) должен быть первым
    expect(items.first['user']['username'], 'A');
    // C (0 партий) — rank 3 (last)
    expect((res['body'] as Map)['total'], 3);
  });

  test('GET /api/leaderboard с невалидным sort → 400', () async {
    final res = await httpGet(
        client, host, port, '/api/leaderboard?sort=password%3B%20DROP');
    expect(res['status'], 400);
  });

  test('GET /api/server-stats → total_games корректен', () async {
    final regA = await httpPost(client, host, port, '/api/register',
        {'username': 'X', 'password_hash': clientHash('X', 'p')});
    final regB = await httpPost(client, host, port, '/api/register',
        {'username': 'Y', 'password_hash': clientHash('Y', 'p')});

    final xId = (regA['body'] as Map)['user']['id'] as int;
    final yId = (regB['body'] as Map)['user']['id'] as int;

    final statsDao2 = StatsDao(appDb.db);
    statsDao2.recordGame(
      roomId: 'S1',
      startedAt: DateTime.now(),
      finishedAt: DateTime.now(),
      participantUserIds: [xId, yId],
      loserUserId: yId,
    );
    statsDao2.recordGame(
      roomId: 'S2',
      startedAt: DateTime.now(),
      finishedAt: DateTime.now(),
      participantUserIds: [xId, yId],
      loserUserId: null,
    );

    final res = await httpGet(client, host, port, '/api/server-stats');
    expect(res['status'], 200);
    expect((res['body'] as Map)['total_games'], 2);
  });

  // --- Шаг 7: аватарки ---

  Future<String> _registerAndGetToken(String username) async {
    final reg = await httpPost(client, host, port, '/api/register', {
      'username': username,
      'password_hash': clientHash(username, 'pass'),
    });
    return (reg['body'] as Map)['token'] as String;
  }

  // Минимальные magic-байты для каждого формата (+ padding до 12 байт)
  final pngBytes = Uint8List.fromList(
      [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0, 0, 0, 0]);
  final jpegBytes = Uint8List.fromList(
      [0xFF, 0xD8, 0xFF, 0xE0, 0, 0, 0, 0, 0, 0, 0, 0]);
  final txtBytes = Uint8List.fromList(
      'Hello World!'.codeUnits);

  const boundary = 'testboundary123';

  test('POST /api/me/avatar PNG → 200, avatar_url содержит .png', () async {
    final token = await _registerAndGetToken('ImgUser1');
    final body = _buildMultipart(boundary, 'file', 'photo.png', pngBytes);
    final res = await httpPostMultipart(
        client, host, port, '/api/me/avatar', body, boundary,
        token: token);
    expect(res['status'], 200);
    final url = (res['body'] as Map)['avatar_url'] as String;
    expect(url, contains('.png'));
  });

  test('POST /api/me/avatar JPEG magic с именем .png → сохранён как .jpg',
      () async {
    final token = await _registerAndGetToken('ImgUser2');
    final body = _buildMultipart(boundary, 'file', 'photo.png', jpegBytes);
    final res = await httpPostMultipart(
        client, host, port, '/api/me/avatar', body, boundary,
        token: token);
    expect(res['status'], 200);
    final url = (res['body'] as Map)['avatar_url'] as String;
    expect(url, contains('.jpg'));
  });

  test('POST /api/me/avatar TXT → 415', () async {
    final token = await _registerAndGetToken('ImgUser3');
    final body = _buildMultipart(boundary, 'file', 'note.txt', txtBytes);
    final res = await httpPostMultipart(
        client, host, port, '/api/me/avatar', body, boundary,
        token: token);
    expect(res['status'], 415);
  });

  test('POST /api/me/avatar >2MB → 413 или closed connection', () async {
    final token = await _registerAndGetToken('ImgUser4');
    final bigBytes = Uint8List(3 * 1024 * 1024);
    final body = _buildMultipart(boundary, 'file', 'big.png', bigBytes);
    try {
      final res = await httpPostMultipart(
          client, host, port, '/api/me/avatar', body, boundary,
          token: token);
      // Сервер успел отдать 413 до разрыва соединения
      expect(res['status'], 413);
    } on SocketException {
      // Сервер закрыл соединение при превышении лимита — ожидаемое поведение
    }
  });

  test('POST /api/me/avatar без токена → 401', () async {
    final body = _buildMultipart(boundary, 'file', 'photo.png', pngBytes);
    final res = await httpPostMultipart(
        client, host, port, '/api/me/avatar', body, boundary);
    expect(res['status'], 401);
  });

  test('GET /avatars/evil..png → 400 (path traversal)', () async {
    final res = await httpGet(client, host, port, '/avatars/evil..png');
    expect(res['status'], 400);
  });

  test('GET /avatars/999.png (нет файла) → 404', () async {
    final res = await httpGet(client, host, port, '/avatars/999.png');
    expect(res['status'], 404);
  });

  test('Загрузка и скачивание аватарки', () async {
    final token = await _registerAndGetToken('ImgUser5');
    final uploadBody =
        _buildMultipart(boundary, 'file', 'avatar.png', pngBytes);
    final upload = await httpPostMultipart(
        client, host, port, '/api/me/avatar', uploadBody, boundary,
        token: token);
    expect(upload['status'], 200);
    final avatarUrl = (upload['body'] as Map)['avatar_url'] as String;

    // avatarUrl = '/avatars/{id}.png'
    final get = await httpGet(client, host, port, avatarUrl);
    expect(get['status'], 200);
  });
}
