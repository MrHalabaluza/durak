import 'dart:io';
import '../db/stats_dao.dart';
import 'handlers_me.dart' show statsJson;
import 'json_io.dart';

Future<void> handleLeaderboard(HttpRequest req, StatsDao stats) async {
  final q = req.uri.queryParameters;
  final sort = q['sort'] ?? 'wins';
  final order = q['order'] ?? 'desc';
  final limit = int.tryParse(q['limit'] ?? '50')?.clamp(1, 200) ?? 50;
  final offset = int.tryParse(q['offset'] ?? '0') ?? 0;

  try {
    final lb = stats.getLeaderboard(
        sort: sort, order: order, limit: limit, offset: offset);
    writeJson(req, {
      'total': lb.total,
      'items': lb.items.asMap().entries.map((e) {
        final item = e.value;
        return {
          'rank': offset + e.key + 1,
          'user': {
            'id': item.user.id,
            'username': item.user.username,
            'avatar_url': item.user.avatarPath == null
                ? null
                : '/${item.user.avatarPath}',
          },
          'stats': statsJson(item.stats),
        };
      }).toList(),
    });
  } on ArgumentError {
    return writeError(req, 400, 'invalid_query', 'sort/order outside whitelist');
  }
}

Future<void> handleServerStats(
    HttpRequest req, StatsDao stats, int onlineUsers) async {
  final s = stats.getServerStats();
  writeJson(req, {
    'total_games': s.totalGames,
    'total_users': s.totalUsers,
    'online_users': onlineUsers,
  });
}
