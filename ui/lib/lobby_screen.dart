import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:flutter/services.dart';
import 'package:durak_logic/durak_logic.dart' hide Card;
import 'package:durak_protocol/durak_protocol.dart';
import 'app_settings.dart';
import 'online_game_screen.dart';
import 'settings_screen.dart';

class LobbyScreen extends StatefulWidget {
  final String host;
  final int port;
  final bool tls;
  final String token;

  /// null — создать комнату, иначе — ID комнаты для входа
  final String? joinRoomId;

  // Режим возврата из игры: уже открытый сокет + известное состояние комнаты.
  final WebSocketChannel? resumeSocket;
  final Stream<Map<String, dynamic>>? resumeStream;
  final String? resumePlayerId;
  final String? resumeRoomId;
  final String? resumeOwnerId;
  final List<({String id, String nickname, bool isBot})> resumePlayers;

  const LobbyScreen({
    super.key,
    required this.host,
    required this.port,
    this.tls = false,
    required this.token,
    this.joinRoomId,
    this.resumeSocket,
    this.resumeStream,
    this.resumePlayerId,
    this.resumeRoomId,
    this.resumeOwnerId,
    this.resumePlayers = const [],
  });

  @override
  State<LobbyScreen> createState() => _LobbyScreenState();
}

enum _Status { connecting, authenticating, connected, error, disconnected }

class _LobbyScreenState extends State<LobbyScreen>
    with WidgetsBindingObserver {
  WebSocketChannel? _socket;
  Stream<Map<String, dynamic>>? _msgStream;
  StreamSubscription? _sub;

  _Status _status = _Status.connecting;
  String? _error;

  String? _roomId;
  String? _myPlayerId;
  String? _ownerId;
  List<({String id, String nickname, bool isBot})> _players = [];
  bool _gameStarted = false;
  Map<String, dynamic>? _latestGameState;

  DeckConfig _deckConfig = DeckConfig();

  bool get _isCreator => widget.joinRoomId == null;
  bool get _isOwner => _myPlayerId != null &&
      (_ownerId == null ? _isCreator : _myPlayerId == _ownerId);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (widget.resumeSocket != null) {
      _socket = widget.resumeSocket;
      _msgStream = widget.resumeStream;
      _myPlayerId = widget.resumePlayerId;
      if (widget.resumeRoomId != null) {
        _roomId = widget.resumeRoomId;
        _ownerId = widget.resumeOwnerId;
        _players = List.of(widget.resumePlayers);
        _status = _Status.connected;
      }
      _sub = _msgStream!.listen(_onMessage, onDone: _onDone, onError: _onError);
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _connect();
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) setState(() {});
  }

  Future<void> _connect() async {
    setState(() {
      _status = _Status.connecting;
      _error = null;
    });
    try {
      final scheme = widget.tls ? 'wss' : 'ws';
      final ws = WebSocketChannel.connect(
          Uri.parse('$scheme://${widget.host}:${widget.port}'));
      await ws.ready;
      if (!mounted) { ws.sink.close(); return; }

      final stream = ws.stream
          .map((data) => jsonDecode(data as String) as Map<String, dynamic>)
          .asBroadcastStream();
      setState(() {
        _socket = ws;
        _msgStream = stream;
        _status = _Status.authenticating;
      });
      _sub = stream.listen(_onMessage, onDone: _onDone, onError: _onError);

      // Step 1: send auth — wait for auth_ok before create/join
      _send(AuthMsg(widget.token).toJson());
    } catch (e) {
      if (mounted) setState(() { _status = _Status.error; _error = e.toString(); });
    }
  }

  void _onMessage(Map<String, dynamic> map) {
    switch (map['type'] as String) {
      case 'auth_ok':
        if (map['deckConfig'] != null) {
          final deck = deckConfigFromJson(map['deckConfig'] as List);
          if (mounted) setState(() => _deckConfig = deck);
        }
        if (mounted) setState(() => _status = _Status.connected);
        // Step 2: now join or create room
        if (_isCreator) {
          _send(const CreateRoomMsg('').toJson());
        } else {
          _send(JoinRoomMsg(widget.joinRoomId!, '').toJson());
        }

      case 'room_joined':
        if (mounted) {
          setState(() {
            _roomId = map['roomId'] as String;
            _myPlayerId = map['playerId'] as String;
          });
        }

      case 'room_state':
        if (mounted) {
          setState(() {
            _roomId = map['roomId'] as String;
            _ownerId = map['ownerId'] as String?;
            _players = (map['players'] as List).map((e) {
              final p = e as Map<String, dynamic>;
              return (
                id: p['id'] as String,
                nickname: p['nickname'] as String? ?? '',
                isBot: p['isBot'] as bool? ?? false,
              );
            }).toList();
            if (_status != _Status.connected) _status = _Status.connected;
          });
        }

      case 'game_state':
        _latestGameState = map;
        if (!_gameStarted && mounted) {
          _gameStarted = true;
          final socket = _socket!;
          _socket = null;
          final msgStream = _msgStream!;
          final myPlayerId = _myPlayerId!;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (_) => OnlineGameScreen(
                  socket: socket,
                  messageStream: msgStream,
                  myPlayerId: myPlayerId,
                  initialState: _latestGameState,
                  host: widget.host,
                  port: widget.port,
                  tls: widget.tls,
                  token: widget.token,
                ),
              ),
            );
          });
        }

      case 'error':
        final msg = map['message'] as String;
        if (msg == 'bad_token' || msg == 'auth_timeout') {
          // Token rejected — clear auth and go back
          AppSettings.clearAuth();
          if (mounted) Navigator.pop(context);
          return;
        }
        if (mounted) setState(() => _error = msg);
    }
  }

  void _onDone() {
    if (mounted) setState(() => _status = _Status.disconnected);
  }

  void _onError(Object e) {
    if (mounted) setState(() { _status = _Status.error; _error = e.toString(); });
  }

  void _send(Map<String, dynamic> msg) => _socket?.sink.add(jsonEncode(msg));

  void _startGame() => _send(const StartGameMsg().toJson());

  Future<void> _editDeckConfig() async {
    final result = await Navigator.push<AppSettings>(
      context,
      MaterialPageRoute(
        builder: (_) => SettingsScreen(
          initial: AppSettings(
            deckConfig: _deckConfig,
            serverHost: widget.host,
            serverPort: widget.port,
            serverTls: widget.tls,
          ),
        ),
      ),
    );
    if (result != null && mounted) {
      setState(() => _deckConfig = result.deckConfig);
      _sendSaveDeck(result.deckConfig);
    }
  }

  void _sendSaveDeck(DeckConfig config) =>
      _send(SaveDeckMsg(config).toJson());

  void _addBot() => _send(const AddBotMsg().toJson());
  void _removeBot(String botId) => _send(RemoveBotMsg(botId).toJson());

  void _leave() {
    _send(const LeaveRoomMsg().toJson());
    _socket?.sink.close();
    if (mounted) Navigator.pop(context);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _sub?.cancel();
    _socket?.sink.close();
    super.dispose();
  }

  // ─────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) { if (!didPop) _leave(); },
      child: Scaffold(
        appBar: AppBar(
          title: Text(_roomId != null ? 'Комната $_roomId' : 'Лобби'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            tooltip: 'Выйти из комнаты',
            onPressed: _leave,
          ),
        ),
        body: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    return switch (_status) {
      _Status.connecting => const _CenteredMessage(
          icon: null,
          text: 'Подключение к серверу...',
          showSpinner: true,
        ),
      _Status.authenticating => const _CenteredMessage(
          icon: null,
          text: 'Авторизация...',
          showSpinner: true,
        ),
      _Status.error || _Status.disconnected => Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.wifi_off, size: 56, color: Colors.red),
                const SizedBox(height: 16),
                Text(
                  _status == _Status.disconnected
                      ? 'Соединение разорвано'
                      : 'Ошибка подключения',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 8),
                  Text(_error!, textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.grey, fontSize: 13)),
                ],
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: _connect,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Переподключиться'),
                ),
              ],
            ),
          ),
        ),
      _Status.connected => _buildLobby(),
    };
  }

  Widget _buildLobby() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_roomId != null) _buildRoomCard(),
          const SizedBox(height: 16),
          if (_isOwner) _buildDeckConfigCard(),
          const SizedBox(height: 16),
          _buildPlayersSection(),
          const SizedBox(height: 16),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(_error!,
                  style: const TextStyle(color: Colors.redAccent, fontSize: 13),
                  textAlign: TextAlign.center),
            ),
          if (_isOwner)
            FilledButton(
              onPressed: _players.length >= 2 ? _startGame : null,
              child: const Text('Начать игру'),
            ),
          if (!_isOwner)
            const Center(
              child: Text('Ожидание начала игры от создателя комнаты...',
                  style: TextStyle(color: Colors.grey)),
            ),
        ],
      ),
    );
  }

  Widget _buildDeckConfigCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Row(
          children: [
            const Icon(Icons.style_outlined, color: Colors.grey),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Колода',
                      style: TextStyle(color: Colors.grey, fontSize: 11)),
                  Text('${_deckConfig.cardCount} карт',
                      style: const TextStyle(fontSize: 15)),
                ],
              ),
            ),
            TextButton(onPressed: _editDeckConfig, child: const Text('Настроить')),
          ],
        ),
      ),
    );
  }

  Widget _buildRoomCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Код комнаты',
                      style: TextStyle(color: Colors.grey, fontSize: 12)),
                  const SizedBox(height: 4),
                  Text(_roomId!,
                      style: const TextStyle(
                          fontSize: 28, fontWeight: FontWeight.bold, letterSpacing: 4)),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.copy),
              tooltip: 'Скопировать код',
              onPressed: () {
                Clipboard.setData(ClipboardData(text: _roomId!));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                      content: Text('Код комнаты скопирован'),
                      duration: Duration(seconds: 2)),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlayersSection() {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('Игроки',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(width: 8),
              Text('${_players.length}/6',
                  style: const TextStyle(color: Colors.grey, fontSize: 16)),
              const Spacer(),
              if (_isOwner && !_gameStarted && _players.length < 6)
                TextButton.icon(
                  onPressed: _addBot,
                  icon: const Icon(Icons.smart_toy_outlined, size: 18),
                  label: const Text('Добавить бота'),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: _players.isEmpty
                ? const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.hourglass_empty, size: 40, color: Colors.grey),
                        SizedBox(height: 8),
                        Text('Ожидание игроков...',
                            style: TextStyle(color: Colors.grey)),
                      ],
                    ),
                  )
                : ListView.separated(
                    itemCount: _players.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 4),
                    itemBuilder: (_, i) => _buildPlayerTile(i),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlayerTile(int index) {
    final p = _players[index];
    final isMe = p.id == _myPlayerId;
    final canRemove = _isOwner && p.isBot && !_gameStarted;
    return ListTile(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: isMe
            ? BorderSide(color: Theme.of(context).colorScheme.primary, width: 1.5)
            : BorderSide.none,
      ),
      tileColor: isMe ? Theme.of(context).colorScheme.primary.withAlpha(20) : null,
      leading: CircleAvatar(
        backgroundColor: isMe ? Theme.of(context).colorScheme.primary : null,
        child: p.isBot
            ? Icon(Icons.smart_toy_outlined,
                size: 20,
                color: isMe ? Colors.white : null)
            : Text('${index + 1}'),
      ),
      title: Text(
        p.nickname.isEmpty
            ? (p.isBot ? 'Бот ${index + 1}' : 'Игрок ${index + 1}')
            : p.nickname,
        style: isMe
            ? TextStyle(
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.primary)
            : null,
      ),
      trailing: canRemove
          ? IconButton(
              icon: const Icon(Icons.remove_circle_outline,
                  color: Colors.redAccent),
              tooltip: 'Убрать бота',
              onPressed: () => _removeBot(p.id),
            )
          : (isMe
              ? Icon(Icons.person,
                  color: Theme.of(context).colorScheme.primary)
              : null),
    );
  }
}

class _CenteredMessage extends StatelessWidget {
  final IconData? icon;
  final String text;
  final bool showSpinner;
  const _CenteredMessage({this.icon, required this.text, this.showSpinner = false});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showSpinner) const CircularProgressIndicator(),
          if (icon != null) Icon(icon, size: 48, color: Colors.grey),
          const SizedBox(height: 16),
          Text(text),
        ],
      ),
    );
  }
}
