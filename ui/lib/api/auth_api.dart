import 'api_client.dart';

class AuthResult {
  final String token;
  final int userId;
  final String username;
  final String? avatarUrl;
  AuthResult({
    required this.token,
    required this.userId,
    required this.username,
    this.avatarUrl,
  });

  factory AuthResult.fromJson(Map<String, dynamic> json) {
    final user = json['user'] as Map<String, dynamic>;
    return AuthResult(
      token: json['token'] as String,
      userId: user['id'] as int,
      username: user['username'] as String,
      avatarUrl: user['avatar_url'] as String?,
    );
  }
}

class AuthApi {
  final ApiClient _client;
  AuthApi(this._client);

  Future<AuthResult> register(String username, String passwordHash) async {
    final body = await _client.postJson('/api/register', {
      'username': username,
      'password_hash': passwordHash,
    });
    return AuthResult.fromJson(body as Map<String, dynamic>);
  }

  Future<AuthResult> login(String username, String passwordHash) async {
    final body = await _client.postJson('/api/login', {
      'username': username,
      'password_hash': passwordHash,
    });
    return AuthResult.fromJson(body as Map<String, dynamic>);
  }

  Future<void> logout() async {
    await _client.postJson('/api/logout', {});
  }
}
