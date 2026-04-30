import 'package:sqlite3/sqlite3.dart';
import 'models.dart';

const _sortWhitelist = {
  'wins',
  'games_played',
  'winrate',
  'losses',
  'draws',
  'last_played_at',
};
const _orderWhitelist = {'asc', 'desc'};

class StatsDao {
  final Database _db;
  StatsDao(this._db);

  UserStatsRow? getUserStats(int userId) {
    final rows = _db.select(
      'SELECT * FROM user_stats WHERE user_id = ?',
      [userId],
    );
    if (rows.isEmpty) return null;
    return UserStatsRow.fromRow(rows.first);
  }

  ({int totalGames, int totalUsers}) getServerStats() {
    final rows = _db.select('SELECT * FROM server_stats WHERE id = 1');
    if (rows.isEmpty) return (totalGames: 0, totalUsers: 0);
    return (
      totalGames: rows.first['total_games'] as int,
      totalUsers: rows.first['total_users'] as int,
    );
  }

  ({int total, List<LeaderboardItem> items}) getLeaderboard({
    required String sort,
    required String order,
    required int limit,
    required int offset,
  }) {
    if (!_sortWhitelist.contains(sort)) {
      throw ArgumentError('Invalid sort field: $sort');
    }
    if (!_orderWhitelist.contains(order)) {
      throw ArgumentError('Invalid order: $order');
    }

    final orderExpr = switch (sort) {
      'winrate' =>
        '((s.wins * 1.0) / NULLIF(s.games_played, 0)) ${order.toUpperCase()} NULLS LAST',
      _ => 's.$sort ${order.toUpperCase()}',
    };

    final totalRows = _db.select(
      'SELECT COUNT(*) as cnt FROM user_stats s',
    );
    final total = totalRows.first['cnt'] as int;

    final rows = _db.select(
      '''
      SELECT u.id, u.username, u.username_lower, u.password_hash, u.avatar_path, u.created_at,
             s.user_id, s.games_played, s.wins, s.losses, s.draws, s.last_played_at
      FROM user_stats s
      JOIN users u ON u.id = s.user_id
      ORDER BY $orderExpr
      LIMIT ? OFFSET ?
      ''',
      [limit, offset],
    );

    final items = rows.map((row) {
      final user = UserRow(
        id: row['id'] as int,
        username: row['username'] as String,
        usernameLower: row['username_lower'] as String,
        passwordHash: row['password_hash'] as String,
        avatarPath: row['avatar_path'] as String?,
        createdAt: row['created_at'] as int,
      );
      final stats = UserStatsRow(
        row['user_id'] as int,
        row['games_played'] as int,
        row['wins'] as int,
        row['losses'] as int,
        row['draws'] as int,
        row['last_played_at'] as int?,
      );
      return LeaderboardItem(user: user, stats: stats);
    }).toList();

    return (total: total, items: items);
  }

  void recordGame({
    required String roomId,
    required DateTime startedAt,
    required DateTime finishedAt,
    required List<int> participantUserIds,
    required int? loserUserId,
  }) {
    _db.execute('BEGIN');
    try {
      final outcome = loserUserId == null ? 'draw' : 'loss';
      _db.execute(
        '''INSERT INTO games (room_id, started_at, finished_at, player_count, outcome, loser_user_id)
           VALUES (?, ?, ?, ?, ?, ?)''',
        [
          roomId,
          startedAt.millisecondsSinceEpoch,
          finishedAt.millisecondsSinceEpoch,
          participantUserIds.length,
          outcome,
          loserUserId,
        ],
      );
      final gameId = _db.lastInsertRowId;
      final now = finishedAt.millisecondsSinceEpoch;

      for (final userId in participantUserIds) {
        final String result;
        if (loserUserId == null) {
          result = 'draw';
        } else if (userId == loserUserId) {
          result = 'loss';
        } else {
          result = 'win';
        }
        _db.execute(
          'INSERT INTO game_players (game_id, user_id, result) VALUES (?, ?, ?)',
          [gameId, userId, result],
        );

        final int wins = result == 'win' ? 1 : 0;
        final int losses = result == 'loss' ? 1 : 0;
        final int draws = result == 'draw' ? 1 : 0;
        _db.execute(
          '''UPDATE user_stats
             SET games_played = games_played + 1,
                 wins = wins + ?,
                 losses = losses + ?,
                 draws = draws + ?,
                 last_played_at = ?
             WHERE user_id = ?''',
          [wins, losses, draws, now, userId],
        );
      }

      _db.execute(
        'UPDATE server_stats SET total_games = total_games + 1 WHERE id = 1',
      );
      _db.execute('COMMIT');
    } catch (e) {
      _db.execute('ROLLBACK');
      rethrow;
    }
  }
}
