import 'package:sqlite3/sqlite3.dart';

class UserRow {
  final int id;
  final String username;
  final String usernameLower;
  final String passwordHash;
  final String? avatarPath;
  final int createdAt;

  const UserRow({
    required this.id,
    required this.username,
    required this.usernameLower,
    required this.passwordHash,
    this.avatarPath,
    required this.createdAt,
  });

  factory UserRow.fromRow(Row row) => UserRow(
        id: row['id'] as int,
        username: row['username'] as String,
        usernameLower: row['username_lower'] as String,
        passwordHash: row['password_hash'] as String,
        avatarPath: row['avatar_path'] as String?,
        createdAt: row['created_at'] as int,
      );
}

class SessionRow {
  final String token;
  final int userId;
  final int createdAt;
  final int lastSeen;

  const SessionRow({
    required this.token,
    required this.userId,
    required this.createdAt,
    required this.lastSeen,
  });

  factory SessionRow.fromRow(Row row) => SessionRow(
        token: row['token'] as String,
        userId: row['user_id'] as int,
        createdAt: row['created_at'] as int,
        lastSeen: row['last_seen'] as int,
      );
}

class UserStatsRow {
  final int userId;
  final int gamesPlayed;
  final int wins;
  final int losses;
  final int draws;
  final int? lastPlayedAt;

  const UserStatsRow(
    this.userId,
    this.gamesPlayed,
    this.wins,
    this.losses,
    this.draws,
    this.lastPlayedAt,
  );

  factory UserStatsRow.fromRow(Row row) => UserStatsRow(
        row['user_id'] as int,
        row['games_played'] as int,
        row['wins'] as int,
        row['losses'] as int,
        row['draws'] as int,
        row['last_played_at'] as int?,
      );
}

class LeaderboardItem {
  final UserRow user;
  final UserStatsRow stats;

  const LeaderboardItem({required this.user, required this.stats});
}
