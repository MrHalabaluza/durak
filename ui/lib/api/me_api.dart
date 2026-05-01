import 'dart:typed_data';
import 'api_client.dart';

class MeApi {
  final ApiClient _client;
  MeApi(this._client);

  Future<Map<String, dynamic>> getMe() async {
    return (await _client.get('/api/me')) as Map<String, dynamic>;
  }

  Future<String?> uploadAvatar(
      Uint8List bytes, String filename, String contentType) async {
    final body = await _client.postMultipart(
        '/api/me/avatar', 'file', bytes, filename, contentType);
    return (body as Map<String, dynamic>?)?['avatar_url'] as String?;
  }
}
