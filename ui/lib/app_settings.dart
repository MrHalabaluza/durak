import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:durak_logic/durak_logic.dart';

class AppSettings {
  final DeckConfig deckConfig;
  final String serverHost;
  final int serverPort;
  final bool serverTls;

  // Auth fields — token in secure storage, rest in prefs
  final String? token;
  final int? userId;
  final String? username;
  final String? avatarUrl;

  static const _keyHost = 'server_host';
  static const _keyPort = 'server_port';
  static const _keyTls = 'server_tls';
  static const _keyDeck = 'deck_config';
  static const _keyUserId = 'user_id';
  static const _keyUsername = 'username';
  static const _keyAvatarUrl = 'avatar_url';
  static const _keyToken = 'auth_token';
  static const _keyRoomId = 'session_room_id';

  static const _secureStorage = FlutterSecureStorage();

  AppSettings({
    DeckConfig? deckConfig,
    this.serverHost = 'localhost',
    this.serverPort = 8080,
    this.serverTls = false,
    this.token,
    this.userId,
    this.username,
    this.avatarUrl,
  }) : deckConfig = deckConfig ?? DeckConfig();

  String get baseHttpUrl =>
      '${serverTls ? 'https' : 'http'}://$serverHost:$serverPort';

  AppSettings copyWith({
    DeckConfig? deckConfig,
    String? serverHost,
    int? serverPort,
    bool? serverTls,
    String? token,
    int? userId,
    String? username,
    String? avatarUrl,
    bool clearAvatar = false,
  }) =>
      AppSettings(
        deckConfig: deckConfig ?? this.deckConfig,
        serverHost: serverHost ?? this.serverHost,
        serverPort: serverPort ?? this.serverPort,
        serverTls: serverTls ?? this.serverTls,
        token: token ?? this.token,
        userId: userId ?? this.userId,
        username: username ?? this.username,
        avatarUrl: clearAvatar ? null : (avatarUrl ?? this.avatarUrl),
      );

  static Future<AppSettings> load() async {
    final (prefs, storedToken) = await (
      SharedPreferences.getInstance(),
      _secureStorage.read(key: _keyToken),
    ).wait;

    final host = prefs.getString(_keyHost) ?? 'localhost';
    final port = prefs.getInt(_keyPort) ?? 8080;
    final tls = prefs.getBool(_keyTls) ?? false;
    final userId = prefs.getInt(_keyUserId);
    final username = prefs.getString(_keyUsername);
    final avatarUrl = prefs.getString(_keyAvatarUrl);

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
      token: storedToken,
      userId: userId,
      username: username,
      avatarUrl: avatarUrl,
    );
  }

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyHost, serverHost);
    await prefs.setInt(_keyPort, serverPort);
    await prefs.setBool(_keyTls, serverTls);
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

  Future<void> saveAuth({
    required String token,
    required int userId,
    required String username,
    String? avatarUrl,
  }) async {
    await _secureStorage.write(key: _keyToken, value: token);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyUserId, userId);
    await prefs.setString(_keyUsername, username);
    if (avatarUrl != null) {
      await prefs.setString(_keyAvatarUrl, avatarUrl);
    } else {
      await prefs.remove(_keyAvatarUrl);
    }
  }

  static Future<void> clearAuth() async {
    await _secureStorage.delete(key: _keyToken);
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyUserId);
    await prefs.remove(_keyUsername);
    await prefs.remove(_keyAvatarUrl);
    await prefs.remove(_keyRoomId);
  }

  static Future<void> saveRoomSession(String roomId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyRoomId, roomId);
  }

  static Future<String?> loadRoomId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyRoomId);
  }

  static Future<void> clearRoomSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyRoomId);
  }
}
