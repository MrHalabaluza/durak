import 'dart:convert';
import 'dart:math';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:durak_logic/durak_logic.dart';

class AppSettings {
  final DeckConfig deckConfig;
  final String serverHost;
  final int serverPort;
  final bool serverTls;
  final String playerName;

  static const _keyHost = 'server_host';
  static const _keyPort = 'server_port';
  static const _keyTls = 'server_tls';
  static const _keyDeck = 'deck_config';
  static const _keyName = 'player_name';

  AppSettings({
    DeckConfig? deckConfig,
    this.serverHost = 'localhost',
    this.serverPort = 8080,
    this.serverTls = false,
    this.playerName = '',
  }) : deckConfig = deckConfig ?? DeckConfig();

  AppSettings copyWith({
    DeckConfig? deckConfig,
    String? serverHost,
    int? serverPort,
    bool? serverTls,
    String? playerName,
  }) =>
      AppSettings(
        deckConfig: deckConfig ?? this.deckConfig,
        serverHost: serverHost ?? this.serverHost,
        serverPort: serverPort ?? this.serverPort,
        serverTls: serverTls ?? this.serverTls,
        playerName: playerName ?? this.playerName,
      );

  static Future<AppSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    final host = prefs.getString(_keyHost) ?? 'localhost';
    final port = prefs.getInt(_keyPort) ?? 8080;
    final tls = prefs.getBool(_keyTls) ?? false;
    var name = prefs.getString(_keyName) ?? '';
    if (name.isEmpty) {
      name = 'Player_${100 + Random().nextInt(900)}';
      await prefs.setString(_keyName, name);
    }
    final deckJson = prefs.getString(_keyDeck);

    DeckConfig deck;
    if (deckJson != null) {
      try {
        final list = jsonDecode(deckJson) as List;
        final counts = <Card, int>{};
        for (final e in list) {
          final m = e as Map<String, dynamic>;
          counts[Card(
            Suit.values.byName(m['suit'] as String),
            Rank.values.byName(m['rank'] as String),
          )] = m['count'] as int;
        }
        deck = DeckConfig.custom(counts);
      } catch (_) {
        deck = DeckConfig();
      }
    } else {
      deck = DeckConfig();
    }

    return AppSettings(
      deckConfig: deck,
      serverHost: host,
      serverPort: port,
      serverTls: tls,
      playerName: name,
    );
  }

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyHost, serverHost);
    await prefs.setInt(_keyPort, serverPort);
    await prefs.setBool(_keyTls, serverTls);
    await prefs.setString(_keyName, playerName);
    final deckEntries = deckConfig.counts.entries
        .where((e) => e.value > 0)
        .map((e) => {
              'suit': e.key.suit.name,
              'rank': e.key.rank.name,
              'count': e.value,
            })
        .toList();
    await prefs.setString(_keyDeck, jsonEncode(deckEntries));
  }
}
