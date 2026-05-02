import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:flutter/services.dart';
import 'package:durak_logic/durak_logic.dart' hide Card;
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

  // Resume-режим: возврат в лобби после партии без переподключения
  final WebSocketChannel? resumeSocket;
  final Stream<Map<String, dynamic>>? resumeStream;
  final String? resumeRoomId;
  final String? resumePlayerId;
  final Map<String, dynamic>? resumeRoomStateMsg;

  const LobbyScreen({
    super.key,
    required this.host,
    required this.port,
    this.tls = false,
    required this.token,
    this.joinRoomId,
    this.resumeSocket,
    this.resumeStream,
    this.resumeRoomId,
    this.resumePlayerId,
    this.resumeRoomStateMsg,
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
  List<({String id, String nickname, int gamesPlayed, int wins, int losses, int draws})> _players = [];
  bool _gameStarted = false;
  Map<String, dynamic>? _latestGameState;

  DeckConfig _deckConfig = DeckConfig();

  bool get _isResuming => widget.resumeSocket != null;

  // В resume-режиме любой игрок может начать следующую партию
  bool get _isCreator => widget.joinRoomId == null || _isResuming;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_isResuming) {
        _resumeFromGame();
      } else {
        _connect();
      }
    });
  }

  void _resumeFromGame() {
    final ws = widget.resumeSocket!;
    final stream = widget.resumeStream!;
    final msg = widget.resumeRoomStateMsg;
    setState(() {
      _socket = ws;
      _msgStream = stream;
      _status = _Status.connected;
      _roomId = widget.resumeRoomId;
      _myPlayerId = widget.resumePlayerId;
      if (msg != null) {
        _roomId = msg['roomId'] as String? ?? widget.resumeRoomId;
        _players = _parsePlayerList(msg['players'] as List);
      }
    });
    _sub = stream.listen(_onMessage, onDone: _onDone, onError: _onError);
  }

  static List<({String id, String nickname, int gamesPlayed, int wins, int losses, int draws})>
      _parsePlayerList(List<dynamic> list) {
    return list.map((e) {
      final p = e as Map<String, dynamic>;
      final s = p['stats'] as Map<String, dynamic>?;
      return (
        id: p['id'] as String,
        nickname: p['nickname'] as String? ?? '',
        gamesPlayed: s?['gamesPlayed'] as int? ?? 0,
        wins: s?['wins'] as int? ?? 0,
        losses: s?['losses'] as int? ?? 0,
        draws: s?['draws'] as int? ?? 0,
      );
    }).toList();
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
      _send({'type': 'auth', 'token': widget.token});
    } catch (e) {
      if (mounted) setState(() { _status = _Status.error; _error = e.toString(); });
    }
  }

  void _onMessage(Map<String, dynamic> map) {
    switch (map['type'] as String) {
      case 'auth_ok':
        if (mounted) setState(() => _status = _Status.connected);
        // Step 2: now join or create room
        if (_isCreator) {
          _send({'type': 'create_room'});
        } else {
          _send({'type': 'join_room', 'roomId': widget.joinRoomId});
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
            _players = _parsePlayerList(map['players'] as List);
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
                  roomId: _roomId!,
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
            serverTls: widget.tls,
          ),
        ),
      ),
    );
    if (result != null && mounted) setState(() => _deckConfig = result.deckConfig);
  }

  void _leave() {
    _send({'type': 'leave_room'});
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
          if (_isCreator) _buildDeckConfigCard(),
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
          if (_isCreator)
            FilledButton(
              onPressed: _players.length >= 2 ? _startGame : null,
              child: const Text('Начать игру'),
            ),
          if (!_isCreator)
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
    return _PlayerTileWithPopup(
      player: p,
      isMe: isMe,
      index: index,
      primaryColor: Theme.of(context).colorScheme.primary,
    );
  }
}

// ─── Player tile with hover/tap stats popup ───────────────────────────────────

typedef _PlayerEntry = ({
  String id,
  String nickname,
  int gamesPlayed,
  int wins,
  int losses,
  int draws,
});

class _PlayerTileWithPopup extends StatefulWidget {
  final _PlayerEntry player;
  final bool isMe;
  final int index;
  final Color primaryColor;

  const _PlayerTileWithPopup({
    required this.player,
    required this.isMe,
    required this.index,
    required this.primaryColor,
  });

  @override
  State<_PlayerTileWithPopup> createState() => _PlayerTileWithPopupState();
}

class _PlayerTileWithPopupState extends State<_PlayerTileWithPopup> {
  OverlayEntry? _overlay;
  final _link = LayerLink();

  @override
  void dispose() {
    _overlay?.remove();
    _overlay = null;
    super.dispose();
  }

  void _showOverlay() {
    if (_overlay != null) return;
    final entry = OverlayEntry(
      builder: (_) => _StatsOverlay(link: _link, player: widget.player),
    );
    _overlay = entry;
    Overlay.of(context).insert(entry);
  }

  void _hideOverlay() {
    _overlay?.remove();
    _overlay = null;
  }

  void _showDialog() {
    _hideOverlay();
    showDialog(
      context: context,
      builder: (_) => _StatsDialog(player: widget.player),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.player;
    final isMe = widget.isMe;
    return CompositedTransformTarget(
      link: _link,
      child: MouseRegion(
        onEnter: (_) => _showOverlay(),
        onExit: (_) => _hideOverlay(),
        child: GestureDetector(
          onTap: _showDialog,
          child: ListTile(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
              side: isMe
                  ? BorderSide(color: widget.primaryColor, width: 1.5)
                  : BorderSide.none,
            ),
            tileColor: isMe ? widget.primaryColor.withAlpha(20) : null,
            leading: CircleAvatar(
              backgroundColor: isMe ? widget.primaryColor : null,
              child: Text('${widget.index + 1}'),
            ),
            title: Text(
              p.nickname.isEmpty ? 'Игрок ${widget.index + 1}' : p.nickname,
              style: isMe
                  ? TextStyle(
                      fontWeight: FontWeight.bold, color: widget.primaryColor)
                  : null,
            ),
            trailing: isMe
                ? Icon(Icons.person, color: widget.primaryColor)
                : null,
          ),
        ),
      ),
    );
  }
}

class _StatsOverlay extends StatelessWidget {
  final LayerLink link;
  final _PlayerEntry player;

  const _StatsOverlay({required this.link, required this.player});

  @override
  Widget build(BuildContext context) {
    return CompositedTransformFollower(
      link: link,
      showWhenUnlinked: false,
      targetAnchor: Alignment.centerRight,
      followerAnchor: Alignment.centerLeft,
      offset: const Offset(8, 0),
      child: Material(
        elevation: 6,
        borderRadius: BorderRadius.circular(10),
        child: _StatsCard(player: player),
      ),
    );
  }
}

class _StatsDialog extends StatelessWidget {
  final _PlayerEntry player;

  const _StatsDialog({required this.player});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: _StatsCard(player: player, padded: true),
    );
  }
}

class _StatsCard extends StatelessWidget {
  final _PlayerEntry player;
  final bool padded;

  const _StatsCard({required this.player, this.padded = false});

  String _pct(int value) {
    if (player.gamesPlayed == 0) return '';
    final pct = (value / player.gamesPlayed * 100).toStringAsFixed(1);
    return ' ($pct%)';
  }

  @override
  Widget build(BuildContext context) {
    final name =
        player.nickname.isEmpty ? 'Игрок' : player.nickname;
    final cs = Theme.of(context).colorScheme;
    final noGames = player.gamesPlayed == 0;

    return Padding(
      padding: EdgeInsets.all(padded ? 20 : 14),
      child: IntrinsicWidth(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.person_outline, size: 18),
                const SizedBox(width: 6),
                Text(name,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 15)),
              ],
            ),
            const SizedBox(height: 8),
            const Divider(height: 1),
            const SizedBox(height: 8),
            if (noGames)
              const Text('Нет сыгранных партий',
                  style: TextStyle(color: Colors.grey, fontSize: 13))
            else ...[
              _Row('Игр сыграно', '${player.gamesPlayed}'),
              _Row('Победы', '${player.wins}${_pct(player.wins)}',
                  color: cs.primary),
              _Row('Поражения', '${player.losses}${_pct(player.losses)}',
                  color: Colors.redAccent),
              _Row('Ничьи', '${player.draws}${_pct(player.draws)}',
                  color: Colors.grey),
            ],
          ],
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  final String label;
  final String value;
  final Color? color;

  const _Row(this.label, this.value, {this.color});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: const TextStyle(fontSize: 13, color: Colors.grey)),
          const SizedBox(width: 24),
          Text(value,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: color)),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

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
