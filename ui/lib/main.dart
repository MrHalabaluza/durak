import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'app_settings.dart';
import 'auth/auth_gate_screen.dart';
import 'lobby_screen.dart';
import 'profile/leaderboard_screen.dart';
import 'profile/profile_screen.dart';
import 'settings_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
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
  AppSettings _settings = AppSettings();
  bool _settingsLoaded = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final s = await AppSettings.load();
    if (!mounted) return;
    setState(() {
      _settings = s;
      _settingsLoaded = true;
    });
    if (s.token == null) {
      _goToAuth();
    }
  }

  void _goToAuth() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => AuthGateScreen(settings: _settings)),
    ).then((_) => _loadSettings()); // reload after auth returns
  }

  Future<void> _openSettings() async {
    final result = await Navigator.push<AppSettings>(
      context,
      MaterialPageRoute(builder: (_) => SettingsScreen(initial: _settings)),
    );
    if (result != null) {
      setState(() => _settings = result);
      result.save();
    }
  }

  void _openProfile() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ProfileScreen(
          settings: _settings,
          onSettingsChanged: (s) => setState(() => _settings = s),
        ),
      ),
    ).then((_) => _loadSettings());
  }

  void _openLeaderboard() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => LeaderboardScreen(settings: _settings)),
    );
  }

  void _createRoom() {
    final token = _settings.token;
    if (token == null) { _goToAuth(); return; }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => LobbyScreen(
          host: _settings.serverHost,
          port: _settings.serverPort,
          tls: _settings.serverTls,
          token: token,
        ),
      ),
    ).then((_) { if (mounted) _loadSettings(); });
  }

  Future<void> _joinRoom() async {
    final code = await showDialog<String>(
      context: context,
      builder: (ctx) => const _JoinRoomDialog(),
    );
    if (code == null || !mounted) return;
    final token = _settings.token;
    if (token == null) { _goToAuth(); return; }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => LobbyScreen(
          host: _settings.serverHost,
          port: _settings.serverPort,
          tls: _settings.serverTls,
          token: token,
          joinRoomId: code,
        ),
      ),
    ).then((_) { if (mounted) _loadSettings(); });
  }

  @override
  Widget build(BuildContext context) {
    if (!_settingsLoaded) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('DTFool'),
        actions: [
          if (_settings.token != null) ...[
            IconButton(
              icon: const Icon(Icons.leaderboard_outlined),
              tooltip: 'Лидерборд',
              onPressed: _openLeaderboard,
            ),
            IconButton(
              icon: const Icon(Icons.account_circle_outlined),
              tooltip: 'Профиль',
              onPressed: _openProfile,
            ),
          ],
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
                _UserCard(
                  username: _settings.username,
                  onLogin: _goToAuth,
                ),
                const SizedBox(height: 16),
                _ServerInfoCard(
                  host: _settings.serverHost,
                  port: _settings.serverPort,
                  onEdit: _openSettings,
                ),
                const SizedBox(height: 32),
                FilledButton.icon(
                  onPressed: _settings.token != null ? _createRoom : null,
                  icon: const Icon(Icons.add),
                  label: const Text('Создать комнату'),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _settings.token != null ? _joinRoom : null,
                  icon: const Icon(Icons.login),
                  label: const Text('Войти по коду'),
                ),
                if (_settings.token == null) ...[
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: _goToAuth,
                    icon: const Icon(Icons.account_circle_outlined),
                    label: const Text('Войти / Зарегистрироваться'),
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

class _UserCard extends StatelessWidget {
  final String? username;
  final VoidCallback onLogin;

  const _UserCard({required this.username, required this.onLogin});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            const Icon(Icons.person_outline, color: Colors.grey),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Игрок',
                      style: TextStyle(color: Colors.grey, fontSize: 11)),
                  Text(
                    username ?? '—',
                    style: const TextStyle(fontSize: 15),
                  ),
                ],
              ),
            ),
            if (username == null)
              TextButton(onPressed: onLogin, child: const Text('Войти')),
          ],
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
                  Text('$host:$port',
                      style: const TextStyle(fontSize: 15)),
                ],
              ),
            ),
            TextButton(onPressed: onEdit, child: const Text('Изменить')),
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
