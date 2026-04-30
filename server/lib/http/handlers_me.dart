import 'dart:io';
import '../auth/auth_service.dart';
import '../db/models.dart';
import '../db/stats_dao.dart';
import 'auth_helper.dart';
import 'json_io.dart';

Future<void> handleGetMe(
    HttpRequest req, AuthService auth, StatsDao stats) async {
  final user = authedUser(req, auth);
  if (user == null) return writeError(req, 401, 'unauthorized', '');
  final s = stats.getUserStats(user.id) ??
      const UserStatsRow(0, 0, 0, 0, 0, null);
  writeJson(req, {
    'user': {
      'id': user.id,
      'username': user.username,
      'avatar_url':
          user.avatarPath == null ? null : '/${user.avatarPath}',
      'created_at': user.createdAt,
    },
    'stats': _statsJson(s),
  });
}

Map<String, dynamic> _statsJson(UserStatsRow s) => {
      'games_played': s.gamesPlayed,
      'wins': s.wins,
      'losses': s.losses,
      'draws': s.draws,
      'winrate':
          s.gamesPlayed == 0 ? null : s.wins / s.gamesPlayed,
      'last_played_at': s.lastPlayedAt,
    };
