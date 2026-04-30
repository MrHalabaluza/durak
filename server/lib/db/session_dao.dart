import 'dart:convert';
import 'dart:math';
import 'package:sqlite3/sqlite3.dart';
import 'models.dart';

class SessionDao {
  final Database _db;
  SessionDao(this._db);

  String create(int userId) {
    final bytes = List.generate(32, (_) => Random.secure().nextInt(256));
    final token = base64Url.encode(bytes);
    final now = DateTime.now().millisecondsSinceEpoch;
    _db.execute(
      'INSERT INTO sessions (token, user_id, created_at, last_seen) VALUES (?, ?, ?, ?)',
      [token, userId, now, now],
    );
    return token;
  }

  SessionRow? find(String token) {
    final rows = _db.select(
      'SELECT * FROM sessions WHERE token = ?',
      [token],
    );
    if (rows.isEmpty) return null;
    return SessionRow.fromRow(rows.first);
  }

  void delete(String token) {
    _db.execute('DELETE FROM sessions WHERE token = ?', [token]);
  }

  void touch(String token) {
    final now = DateTime.now().millisecondsSinceEpoch;
    _db.execute(
      'UPDATE sessions SET last_seen = ? WHERE token = ?',
      [now, token],
    );
  }
}
