import 'dart:convert';
import 'package:durak_logic/durak_logic.dart';
import 'package:sqlite3/sqlite3.dart';

class DeckDao {
  final Database _db;
  DeckDao(this._db);

  /// Returns the user's saved deck, or null if not set (caller should use default).
  DeckConfig? load(int userId) {
    final rows = _db.select(
      'SELECT deck_config FROM user_decks WHERE user_id = ?',
      [userId],
    );
    if (rows.isEmpty) return null;
    return _fromJson(rows.first['deck_config'] as String);
  }

  void save(int userId, DeckConfig config) {
    final json = _toJson(config);
    _db.execute(
      'INSERT INTO user_decks (user_id, deck_config) VALUES (?, ?)'
      '  ON CONFLICT(user_id) DO UPDATE SET deck_config = excluded.deck_config',
      [userId, json],
    );
  }

  static DeckConfig _fromJson(String raw) {
    final list = jsonDecode(raw) as List;
    final counts = <Card, int>{};
    for (final e in list) {
      final m = e as Map<String, dynamic>;
      final count = m['count'] as int;
      if (count > 0) {
        counts[Card(
          Suit.values.byName(m['suit'] as String),
          Rank.values.byName(m['rank'] as String),
        )] = count;
      }
    }
    return DeckConfig.custom(counts);
  }

  static String _toJson(DeckConfig config) {
    final list = config.counts.entries
        .where((e) => e.value > 0)
        .map((e) => {
              'suit': e.key.suit.name,
              'rank': e.key.rank.name,
              'count': e.value,
            })
        .toList();
    return jsonEncode(list);
  }

  /// Serializes a DeckConfig to the same list format used in WebSocket messages.
  static List<Map<String, dynamic>> toWireFormat(DeckConfig config) {
    return config.counts.entries
        .where((e) => e.value > 0)
        .map((e) => {
              'suit': e.key.suit.name,
              'rank': e.key.rank.name,
              'count': e.value,
            })
        .toList();
  }
}
