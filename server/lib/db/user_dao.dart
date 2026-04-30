import 'package:sqlite3/sqlite3.dart';
import 'models.dart';

class UserDao {
  final Database _db;
  UserDao(this._db);

  int create({required String username, required String passwordHash}) {
    final now = DateTime.now().millisecondsSinceEpoch;
    _db.execute(
      'INSERT INTO users (username, username_lower, password_hash, created_at) VALUES (?, ?, ?, ?)',
      [username, username.toLowerCase(), passwordHash, now],
    );
    final id = _db.lastInsertRowId;
    _db.execute(
      'INSERT INTO user_stats (user_id, games_played, wins, losses, draws) VALUES (?, 0, 0, 0, 0)',
      [id],
    );
    _db.execute(
      'UPDATE server_stats SET total_users = total_users + 1 WHERE id = 1',
    );
    return id;
  }

  UserRow? findById(int id) {
    final rows = _db.select('SELECT * FROM users WHERE id = ?', [id]);
    if (rows.isEmpty) return null;
    return UserRow.fromRow(rows.first);
  }

  UserRow? findByUsernameLower(String lower) {
    final rows = _db.select(
      'SELECT * FROM users WHERE username_lower = ?',
      [lower],
    );
    if (rows.isEmpty) return null;
    return UserRow.fromRow(rows.first);
  }

  void updateAvatarPath(int userId, String? path) {
    _db.execute(
      'UPDATE users SET avatar_path = ? WHERE id = ?',
      [path, userId],
    );
  }
}
