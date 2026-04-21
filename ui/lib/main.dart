import 'package:flutter/material.dart';
import 'package:durak_logic/durak_logic.dart';
import 'game_screen.dart';
import 'settings_screen.dart';

void main() {
  runApp(const DurakApp());
}

class DurakApp extends StatelessWidget {
  const DurakApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'DTFool',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true).copyWith(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.green,
          brightness: Brightness.dark,
        ),
      ),
      home: const SetupScreen(),
    );
  }
}

class SetupScreen extends StatefulWidget {
  const SetupScreen({super.key});

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  int _playerCount = 2;
  DeckConfig _deckConfig = const DeckConfig();

  Future<void> _openSettings() async {
    final result = await Navigator.push<DeckConfig>(
      context,
      MaterialPageRoute(
        builder: (_) => SettingsScreen(initial: _deckConfig),
      ),
    );
    if (result != null) setState(() => _deckConfig = result);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('DTFool — Двойной переводной дурак'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: 'Настройки',
            onPressed: _openSettings,
          ),
        ],
      ),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Количество игроков', style: TextStyle(fontSize: 20)),
            const SizedBox(height: 16),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.remove),
                  onPressed: _playerCount > 2
                      ? () => setState(() => _playerCount--)
                      : null,
                ),
                Text('$_playerCount', style: const TextStyle(fontSize: 32)),
                IconButton(
                  icon: const Icon(Icons.add),
                  onPressed: _playerCount < 6
                      ? () => setState(() => _playerCount++)
                      : null,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Колода: ${_deckConfig.cardCount} карт',
              style: const TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 32),
            FilledButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => GameScreen(
                    playerCount: _playerCount,
                    deckConfig: _deckConfig,
                  ),
                ),
              ),
              child: const Text('Начать игру'),
            ),
          ],
        ),
      ),
    );
  }
}
