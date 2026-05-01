import 'api_client.dart';

class StatsApi {
  final ApiClient _client;
  StatsApi(this._client);

  Future<Map<String, dynamic>> getLeaderboard({
    String sort = 'wins',
    String order = 'desc',
    int limit = 50,
    int offset = 0,
  }) async {
    final q = 'sort=$sort&order=$order&limit=$limit&offset=$offset';
    return (await _client.get('/api/leaderboard?$q')) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> getServerStats() async {
    return (await _client.get('/api/server-stats')) as Map<String, dynamic>;
  }
}
