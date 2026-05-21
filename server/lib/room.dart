import 'dart:async';
import 'package:durak_logic/durak_logic.dart';
import 'bot_strategy.dart';
import 'connection.dart';
import 'db/stats_dao.dart';
import 'protocol.dart';

class _BotEntry {
  final String id;
  final String nickname;
  final BotStrategy strategy;
  _BotEntry({required this.id, required this.nickname, required this.strategy});
}

class Room {
  final String id;
  final StatsDao _stats;
  final List<Connection> _connections = [];
  final List<_BotEntry> _bots = [];
  Game? _game;
  DateTime? _startedAt;
  bool _finishedRecorded = false;

  String? _ownerId;
  String? get ownerId => _ownerId;

  bool _botActing = false;
  int _botCounter = 0;
  Timer? _botTimer;

  Room(this.id, this._stats);

  bool get isStarted => _game != null;
  bool get isEmpty => _connections.isEmpty;

  List<String> get playerIds => [
        ..._connections.map((c) => c.playerId!),
        ..._bots.map((b) => b.id),
      ];

  List<({String id, String nickname, bool isBot})> get playerEntries => [
        ..._connections.map(
            (c) => (id: c.playerId!, nickname: c.nickname, isBot: false)),
        ..._bots.map((b) => (id: b.id, nickname: b.nickname, isBot: true)),
      ];

  bool addPlayer(Connection conn) {
    if (isStarted || _connections.length + _bots.length >= 6) return false;
    _connections.add(conn);
    conn.room = this;
    _ownerId ??= conn.playerId!;
    return true;
  }

  void removePlayer(Connection conn) {
    _connections.remove(conn);
    conn.room = null;
    if (_connections.isEmpty) {
      _botTimer?.cancel();
      _botActing = false;
    }
    // Mid-game disconnects leave the player's slot in the game state.
    // Their turn will stall until reconnection is implemented (future work).
  }

  bool addBot() {
    if (isStarted || _connections.length + _bots.length >= 6) return false;
    _botCounter++;
    _bots.add(_BotEntry(
      id: 'bot_$_botCounter',
      nickname: 'Бот ${_bots.length + 1}',
      strategy: SimpleBot(),
    ));
    return true;
  }

  bool removeBot(String botId) {
    final idx = _bots.indexWhere((b) => b.id == botId);
    if (idx == -1) return false;
    _bots.removeAt(idx);
    return true;
  }

  bool startGame([DeckConfig? config]) {
    if (isStarted || _connections.length + _bots.length < 2) return false;
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
    if (_game == null) return;
    final state = _game!.state;
    final addingIds = _game!.addingPlayerIds;
    final nicks = {
      for (final c in _connections) c.playerId!: c.nickname,
      for (final b in _bots) b.id: b.nickname,
    };
    for (final conn in _connections) {
      conn.send(gameStateMsg(state, conn.playerId!, addingIds, nicks));
    }
    if (state.phase == GamePhase.finished && !_finishedRecorded) {
      _finishedRecorded = true;
      try {
        final botIds = _bots.map((b) => b.id).toSet();
        final loserIsBot =
            state.loserId != null && botIds.contains(state.loserId);
        _stats.recordGame(
          roomId: id,
          startedAt: _startedAt!,
          finishedAt: DateTime.now(),
          participantUserIds:
              _connections.map((c) => int.parse(c.playerId!)).toList(),
          loserUserId: loserIsBot
              ? null
              : (state.loserId == null ? null : int.parse(state.loserId!)),
        );
      } catch (e, st) {
        // ignore: avoid_print
        print('recordGame failed: $e\n$st');
      }
      broadcast({'type': 'game_over', 'loserId': state.loserId});
      _resetForNewGame();
    }
    _scheduleBotAction();
  }

  void _resetForNewGame() {
    if (_connections.isEmpty) return;
    _game = null;
    _finishedRecorded = false;
    _startedAt = null;
    _botActing = false;
    _botTimer?.cancel();
    broadcast(roomStateMsg(id, playerEntries, false, ownerId: _ownerId));
  }

  void _scheduleBotAction() {
    if (_botActing) return;
    if (_game == null || _game!.state.phase == GamePhase.finished) return;

    final state = _game!.state;
    _BotEntry? entry;

    switch (state.phase) {
      case GamePhase.attacking:
        entry = _bots
            .where((b) => b.id == state.attacker.id)
            .firstOrNull;
      case GamePhase.defending:
        entry = _bots
            .where((b) => b.id == state.defender.id)
            .firstOrNull;
      case GamePhase.adding || GamePhase.taking:
        final currentId = state.players[state.currentAdderIndex].id;
        entry = _bots.where((b) => b.id == currentId).firstOrNull;
      case GamePhase.finished:
        return;
    }

    if (entry == null) return;

    _botActing = true;
    final bot = entry;
    _botTimer?.cancel();
    _botTimer = Timer(const Duration(milliseconds: 700), () {
      _botActing = false;
      if (_game == null || _game!.state.phase == GamePhase.finished) return;
      final action = bot.strategy.chooseAction(
        _game!.state,
        bot.id,
        _game!.addingPlayerIds,
      );
      _executeBotAction(bot.id, action);
    });
  }

  void _executeBotAction(String botId, BotAction action) {
    try {
      switch (action) {
        case BotAttack(:final cards):
          _game!.attack(botId, cards);
        case BotDefend(:final attackCard, :final defenseCard):
          _game!.defend(botId, attackCard, defenseCard);
        case BotTransfer(:final cards):
          _game!.transfer(botId, cards);
        case BotTransit(:final card):
          _game!.transit(botId, card);
        case BotAddAttack(:final cards):
          _game!.addAttack(botId, cards);
        case BotPass():
          _game!.pass(botId);
        case BotTake():
          _game!.take(botId);
      }
      broadcastGameState();
    } on GameException catch (e) {
      // ignore: avoid_print
      print('Bot $botId illegal action: ${e.message}. Falling back.');
      try {
        if (_game!.state.phase == GamePhase.defending &&
            _game!.state.defender.id == botId) {
          _game!.take(botId);
        } else {
          _game!.pass(botId);
        }
        broadcastGameState();
      } on GameException catch (e2) {
        // ignore: avoid_print
        print('Bot $botId fallback also failed: ${e2.message}');
      }
    }
  }
}
