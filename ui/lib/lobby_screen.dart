import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:durak_logic/durak_logic.dart' hide Card;
import 'app_settings.dart';
import 'online_game_screen.dart';
import 'settings_screen.dart';

class LobbyScreen extends StatefulWidget {
  final String host;
  final int port;

  /// null — создать комнату, иначе — ID комнаты для входа
  final String? joinRoomId;

  const LobbyScreen({
    super.key,
    required this.host,
    required this.port,
    this.joinRoomId,
  });

  @override
  State<LobbyScreen> createState() => _LobbyScreenState();
}

enum _Status { connecting, connected, error, disconnected }

class _LobbyScreenState extends State<LobbyScreen>
    with WidgetsBindingObserver {
  WebSocket? _socket;
  Stream<Map<String, dynamic>>? _msgStream;
  StreamSubscription? _sub;

  _Status _status = _Status.connecting;
  String? _error;

  String? _roomId;
  String? _myPlayerId;
  List<String> _players = [];
  bool _gameStarted = false;

  DeckConfig _deckConfig = DeckConfig();

  bool get _isCreator => widget.joinRoomId == null;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Defer until after first build so setState / Navigator calls in _connect
    // don't fire before the widget tree is fully mounted (avoids
    // _dependents.isEmpty assertion from calling setState in initState).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _connect();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      setState(() {});
    }
  }

  Future<void> _connect() async {
    setState(() {
      _status = _Status.connecting;
      _error = null;
    });
    try {
      final ws =
          await WebSocket.connect('ws://${widget.host}:${widget.port}');
      if (!mounted) {
        ws.close();
        return;
      }
      // Convert to broadcast so OnlineGameScreen can subscribe without
      // "Stream has already been listened to" error.
      final stream = ws
          .map((data) => jsonDecode(data as String) as Map<String, dynamic>)
          .asBroadcastStream();
      setState(() {
        _socket = ws;
        _msgStream = stream;
        _status = _Status.connected;
      });
      _sub = stream.listen(_onMessage, onDone: _onDone, onError: _onError);
      _send(_isCreator
          ? {'type': 'create_room'}
          : {'type': 'join_room', 'roomId': widget.joinRoomId});
    } catch (e) {
      if (mounted) {
        setState(() {
          _status = _Status.error;
          _error = e.toString();
        });
      }
    }
  }

  void _onMessage(Map<String, dynamic> map) {
    switch (map['type'] as String) {
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
            _players = List<String>.from(map['players'] as List);
          });
        }
      case 'game_state':
        if (!_gameStarted && mounted) {
          _gameStarted = true;
          // Don't cancel _sub here — let dispose() do it after
          // OnlineGameScreen.initState() has already subscribed to the
          // broadcast stream. Cancelling here would kill the source
          // before the game screen subscribes.
          final socket = _socket!;
          _socket = null; // dispose() won't close a socket we handed off
          final msgStream = _msgStream!;
          final myPlayerId = _myPlayerId!;
          // Defer navigation to the next frame so it never fires during a
          // build phase, which would violate the _dependents.isEmpty
          // invariant on InheritedElements.
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (_) => OnlineGameScreen(
                  socket: socket,
                  messageStream: msgStream,
                  myPlayerId: myPlayerId,
                  initialState: map,
                ),
              ),
            );
          });
        }
      case 'error':
        if (mounted) setState(() => _error = map['message'] as String);
    }
  }

  void _onDone() {
    if (mounted) setState(() => _status = _Status.disconnected);
  }

  void _onError(Object e) {
    if (mounted) {
      setState(() {
        _status = _Status.error;
        _error = e.toString();
      });
    }
  }

  void _send(Map<String, dynamic> msg) =>
      _socket?.add(jsonEncode(msg));

  void _startGame() {
    final config = _deckConfig.counts.entries
        .map((e) => {
              'suit': e.key.suit.name,
              'rank': e.key.rank.name,
              'count': e.value,
            })
        .toList();
    _send({'type': 'start_game', 'deckConfig': config});
  }

  Future<void> _editDeckConfig() async {
    final result = await Navigator.push<AppSettings>(
      context,
      MaterialPageRoute(
        builder: (_) => SettingsScreen(
          initial: AppSettings(
            deckConfig: _deckConfig,
            serverHost: widget.host,
            serverPort: widget.port,
          ),
        ),
      ),
    );
    if (result != null && mounted) {
      setState(() => _deckConfig = result.deckConfig);
    }
  }

  void _leave() {
    _send({'type': 'leave_room'});
    _socket?.close();
    if (mounted) Navigator.pop(context);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _sub?.cancel();
    _socket?.close();
    super.dispose();
  }

  // ─────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) => _leave(),
      child: Scaffold(
        appBar: AppBar(
          title:
              Text(_roomId != null ? 'Комната $_roomId' : 'Лобби'),
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
    switch (_status) {
      case _Status.connecting:
        return const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Подключение к серверу...'),
            ],
          ),
        );

      case _Status.error:
      case _Status.disconnected:
        return Center(
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
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.bold),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    _error!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.grey, fontSize: 13),
                  ),
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
        );

      case _Status.connected:
        return _buildLobby();
    }
  }

  Widget _buildLobby() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_roomId != null) _buildRoomCard(),
          const SizedBox(height: 16),
          if (_isCreator) _buildDeckConfigCard(),
          const SizedBox(height: 16),
          _buildPlayersSection(),
          const SizedBox(height: 16),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                _error!,
                style:
                    const TextStyle(color: Colors.redAccent, fontSize: 13),
                textAlign: TextAlign.center,
              ),
            ),
          if (_isCreator)
            FilledButton(
              onPressed: _players.length >= 2 ? _startGame : null,
              child: const Text('Начать игру'),
            ),
          if (!_isCreator)
            const Center(
              child: Text(
                'Ожидание начала игры от создателя комнаты...',
                style: TextStyle(color: Colors.grey),
              ),
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
                  Text(
                    '${_deckConfig.cardCount} карт',
                    style: const TextStyle(fontSize: 15),
                  ),
                ],
              ),
            ),
            TextButton(
              onPressed: _editDeckConfig,
              child: const Text('Настроить'),
            ),
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
                  const Text(
                    'Код комнаты',
                    style: TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _roomId!,
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 4,
                    ),
                  ),
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
                    duration: Duration(seconds: 2),
                  ),
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
              const Text(
                'Игроки',
                style:
                    TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(width: 8),
              Text(
                '${_players.length}/6',
                style: const TextStyle(color: Colors.grey, fontSize: 16),
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
                        Icon(Icons.hourglass_empty,
                            size: 40, color: Colors.grey),
                        SizedBox(height: 8),
                        Text('Ожидание игроков...',
                            style: TextStyle(color: Colors.grey)),
                      ],
                    ),
                  )
                : ListView.separated(
                    itemCount: _players.length,
                    separatorBuilder: (_, i) =>
                        const SizedBox(height: 4),
                    itemBuilder: (_, i) => _buildPlayerTile(i),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlayerTile(int index) {
    final id = _players[index];
    final isMe = id == _myPlayerId;
    final shortId =
        id.length > 12 ? '${id.substring(0, 6)}…' : id;

    return ListTile(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: isMe
            ? BorderSide(
                color: Theme.of(context).colorScheme.primary, width: 1.5)
            : BorderSide.none,
      ),
      tileColor: isMe
          ? Theme.of(context).colorScheme.primary.withAlpha(20)
          : null,
      leading: CircleAvatar(
        backgroundColor: isMe
            ? Theme.of(context).colorScheme.primary
            : null,
        child: Text('${index + 1}'),
      ),
      title: Text(
        isMe ? 'Вы' : 'Игрок ${index + 1}',
        style: isMe
            ? TextStyle(
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.primary)
            : null,
      ),
      subtitle: Text(
        shortId,
        style: const TextStyle(color: Colors.grey, fontSize: 11),
      ),
      trailing: isMe
          ? Icon(Icons.person,
              color: Theme.of(context).colorScheme.primary)
          : null,
    );
  }
}
