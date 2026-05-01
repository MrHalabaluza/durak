import 'api_client.dart';

class UsersApi {
  final ApiClient _client;
  UsersApi(this._client);

  Future<Map<String, dynamic>> getUser(int id) async {
    return (await _client.get('/api/users/$id')) as Map<String, dynamic>;
  }
}
