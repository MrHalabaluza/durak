import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'app_settings.dart';
import 'game_screen.dart';
import 'lobby_screen.dart';
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

enum _GameMode { local, online }

class SetupScreen extends StatefulWidget {
  const SetupScreen({super.key});

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  int _playerCount = 2;
  AppSettings _settings = AppSettings();
  _GameMode _mode = _GameMode.local;

  Future<void> _openSettings() async {
    final result = await Navigator.push<AppSettings>(
      context,
      MaterialPageRoute(
        builder: (_) => SettingsScreen(initial: _settings),
      ),
    );
    if (result != null) setState(() => _settings = result);
  }

  void _startLocal() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => GameScreen(
          playerCount: _playerCount,
          deckConfig: _settings.deckConfig,
        ),
      ),
    );
  }

  void _createRoom() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => LobbyScreen(
          host: _settings.serverHost,
          port: _settings.serverPort,
        ),
      ),
    );
  }

  Future<void> _joinRoom() async {
    final code = await showDialog<String>(
      context: context,
      builder: (ctx) => const _JoinRoomDialog(),
    );
    if (code == null || !mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => LobbyScreen(
          host: _settings.serverHost,
          port: _settings.serverPort,
          joinRoomId: code,
        ),
      ),
    );
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
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Mode toggle
                SegmentedButton<_GameMode>(
                  segments: const [
                    ButtonSegment(
                      value: _GameMode.local,
                      icon: Icon(Icons.people),
                      label: Text('Локальная игра'),
                    ),
                    ButtonSegment(
                      value: _GameMode.online,
                      icon: Icon(Icons.wifi),
                      label: Text('Онлайн'),
                    ),
                  ],
                  selected: {_mode},
                  onSelectionChanged: (s) =>
                      setState(() => _mode = s.first),
                ),
                const SizedBox(height: 32),

                if (_mode == _GameMode.local) ...[
                  const Text('Количество игроков',
                      style: TextStyle(fontSize: 18),
                      textAlign: TextAlign.center),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.remove),
                        onPressed: _playerCount > 2
                            ? () => setState(() => _playerCount--)
                            : null,
                      ),
                      Text('$_playerCount',
                          style: const TextStyle(fontSize: 36)),
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
                    'Колода: ${_settings.deckConfig.cardCount} карт',
                    style: const TextStyle(color: Colors.grey),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 32),
                  FilledButton(
                    onPressed: _startLocal,
                    child: const Text('Начать игру'),
                  ),
                ] else ...[
                  // Online mode — server info
                  _ServerInfoCard(
                    host: _settings.serverHost,
                    port: _settings.serverPort,
                    onEdit: _openSettings,
                  ),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: _createRoom,
                    icon: const Icon(Icons.add),
                    label: const Text('Создать комнату'),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: _joinRoom,
                    icon: const Icon(Icons.login),
                    label: const Text('Войти по коду'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ServerInfoCard extends StatelessWidget {
  final String host;
  final int port;
  final VoidCallback onEdit;

  const _ServerInfoCard({
    required this.host,
    required this.port,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            const Icon(Icons.dns_outlined, color: Colors.grey),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Сервер',
                      style: TextStyle(color: Colors.grey, fontSize: 11)),
                  Text(
                    '$host:$port',
                    style: const TextStyle(fontSize: 15),
                  ),
                ],
              ),
            ),
            TextButton(
              onPressed: onEdit,
              child: const Text('Изменить'),
            ),
          ],
        ),
      ),
    );
  }
}

class _JoinRoomDialog extends StatefulWidget {
  const _JoinRoomDialog();

  @override
  State<_JoinRoomDialog> createState() => _JoinRoomDialogState();
}

class _JoinRoomDialogState extends State<_JoinRoomDialog> {
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Войти в комнату'),
      content: TextField(
        controller: _ctrl,
        autofocus: true,
        decoration: const InputDecoration(
          labelText: 'Код комнаты',
          hintText: 'Введите код',
        ),
        textCapitalization: TextCapitalization.characters,
        inputFormatters: [
          FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9]')),
          LengthLimitingTextInputFormatter(10),
        ],
        onSubmitted: (v) {
          if (v.trim().isNotEmpty) Navigator.pop(context, v.trim());
        },
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Отмена'),
        ),
        FilledButton(
          onPressed: () {
            final v = _ctrl.text.trim();
            if (v.isNotEmpty) Navigator.pop(context, v);
          },
          child: const Text('Войти'),
        ),
      ],
    );
  }
}
