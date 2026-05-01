import 'package:durak_logic/durak_logic.dart';
import 'connection.dart';
import 'db/stats_dao.dart';
import 'protocol.dart';

class Room {
  final String id;
  final StatsDao _stats;
  final List<Connection> _connections = [];
  final Map<String, String> _disconnectedPlayers = {};
  Game? _game;
  DateTime? _startedAt;
  bool _finishedRecorded = false;

  Room(this.id, this._stats);

  bool get isStarted => _game != null;
  bool get isEmpty => _connections.isEmpty && _disconnectedPlayers.isEmpty;
  List<String> get playerIds =>
      _connections.map((c) => c.playerId!).toList();
  List<({String id, String nickname})> get playerEntries =>
      _connections.map((c) => (id: c.playerId!, nickname: c.nickname)).toList();

  bool addPlayer(Connection conn) {
    if (isStarted || _connections.length >= 6) return false;
    _connections.add(conn);
    conn.room = this;
    return true;
  }

  void removePlayer(Connection conn, {bool disconnected = false}) {
    _connections.remove(conn);
    conn.room = null;
    if (disconnected &&
        isStarted &&
        _game!.state.phase != GamePhase.finished &&
        conn.playerId != null) {
      _disconnectedPlayers[conn.playerId!] = conn.nickname;
    }
  }

  bool rejoinPlayer(Connection conn) {
    final pid = conn.playerId!;
    if (!isStarted || !_disconnectedPlayers.containsKey(pid)) return false;
    conn.nickname = _disconnectedPlayers.remove(pid)!;
    _connections.add(conn);
    conn.room = this;
    return true;
  }

  void sendGameStateTo(Connection conn) {
    if (_game == null) return;
    final state = _game!.state;
    final addingIds = _game!.addingPlayerIds;
    conn.send(gameStateMsg(state, conn.playerId!, addingIds, _allNicknames()));
  }

  Map<String, String> _allNicknames() => {
        for (final c in _connections) c.playerId!: c.nickname,
        ..._disconnectedPlayers,
      };

  bool startGame([DeckConfig? config]) {
    if (isStarted || _connections.length < 2) return false;
    _startedAt = DateTime.now();
    try {
      _game = Game.start(playerIds, config: config);
    } on GameException catch (e) {
      for (final c in _connections) c.send(errorMsg(e.message));
      return false;
    }
    broadcastGameState();
    return true;
  }

  /// For testing: inject a game (e.g. already-finished) and trigger broadcast.
  void injectGame(Game game, DateTime startedAt) {
    _game = game;
    _startedAt = startedAt;
  }

  void handleAttack(Connection conn, List<Card> cards) =>
      _run(conn, () => _game!.attack(conn.playerId!, cards));

  void handleDefend(Connection conn, Card attackCard, Card defenseCard) =>
      _run(conn, () => _game!.defend(conn.playerId!, attackCard, defenseCard));

  void handleTransfer(Connection conn, List<Card> cards) =>
      _run(conn, () => _game!.transfer(conn.playerId!, cards));

  void handleTransit(Connection conn, Card card) =>
      _run(conn, () => _game!.transit(conn.playerId!, card));

  void handleAddAttack(Connection conn, List<Card> cards) =>
      _run(conn, () => _game!.addAttack(conn.playerId!, cards));

  void handlePass(Connection conn) =>
      _run(conn, () => _game!.pass(conn.playerId!));

  void handleTake(Connection conn) =>
      _run(conn, () => _game!.take(conn.playerId!));

  void broadcast(Map<String, dynamic> message) {
    for (final conn in _connections) {
      conn.send(message);
    }
  }

  void _run(Connection conn, void Function() action) {
    try {
      action();
      broadcastGameState();
    } on GameException catch (e) {
      conn.send(errorMsg(e.message));
    }
  }

  void broadcastGameState() {
    final state = _game!.state;
    final addingIds = _game!.addingPlayerIds;
    final nicks = _allNicknames();
    for (final conn in _connections) {
      conn.send(gameStateMsg(state, conn.playerId!, addingIds, nicks));
    }
    if (state.phase == GamePhase.finished && !_finishedRecorded) {
      _finishedRecorded = true;
      try {
        _stats.recordGame(
          roomId: id,
          startedAt: _startedAt!,
          finishedAt: DateTime.now(),
          participantUserIds:
              _connections.map((c) => int.parse(c.playerId!)).toList(),
          loserUserId:
              state.loserId == null ? null : int.parse(state.loserId!),
        );
      } catch (e, st) {
        // ignore: avoid_print
        print('recordGame failed: $e\n$st');
      }
      broadcast({'type': 'game_over', 'loserId': state.loserId});
    }
  }
}
