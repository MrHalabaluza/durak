import 'dart:io';
import '../auth/auth_service.dart';
import 'json_io.dart';

Future<void> handleRegister(HttpRequest req, AuthService auth) async {
  final body = await readJsonBody(req);
  final username = body['username'] as String?;
  final passwordHash = body['password_hash'] as String?;
  if (username == null ||
      passwordHash == null ||
      passwordHash.length != 64) {
    return writeError(
        req, 400, 'invalid_request', 'username and password_hash required');
  }
  try {
    final res =
        auth.register(username: username, clientPasswordHash: passwordHash);
    writeJson(req, {
      'token': res.token,
      'user': {
        'id': res.userId,
        'username': res.username,
        'avatar_url': null,
      },
    }, status: 201);
  } on AuthException catch (e) {
    final status = e.code == 'username_taken' ? 409 : 400;
    writeError(req, status, e.code, e.message);
  }
}

Future<void> handleLogin(HttpRequest req, AuthService auth) async {
  final body = await readJsonBody(req);
  final username = body['username'] as String?;
  final passwordHash = body['password_hash'] as String?;
  if (username == null || passwordHash == null) {
    return writeError(
        req, 400, 'invalid_request', 'username and password_hash required');
  }
  try {
    final res =
        auth.login(username: username, clientPasswordHash: passwordHash);
    writeJson(req, {
      'token': res.token,
      'user': {
        'id': res.userId,
        'username': res.username,
        'avatar_url':
            res.avatarPath == null ? null : '/${res.avatarPath}',
      },
    });
  } on AuthException catch (e) {
    writeError(req, 401, e.code, e.message);
  }
}

Future<void> handleLogout(HttpRequest req, AuthService auth) async {
  final h = req.headers.value('authorization');
  if (h == null || !h.startsWith('Bearer ')) {
    return writeError(req, 401, 'unauthorized', 'Bearer token required');
  }
  auth.logout(h.substring(7));
  req.response.statusCode = 204;
  await req.response.close();
}
