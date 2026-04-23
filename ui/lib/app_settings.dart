import 'package:durak_logic/durak_logic.dart';

class AppSettings {
  final DeckConfig deckConfig;
  final String serverHost;
  final int serverPort;

  AppSettings({
    DeckConfig? deckConfig,
    this.serverHost = 'localhost',
    this.serverPort = 8080,
  }) : deckConfig = deckConfig ?? DeckConfig();

  AppSettings copyWith({
    DeckConfig? deckConfig,
    String? serverHost,
    int? serverPort,
  }) =>
      AppSettings(
        deckConfig: deckConfig ?? this.deckConfig,
        serverHost: serverHost ?? this.serverHost,
        serverPort: serverPort ?? this.serverPort,
      );
}
