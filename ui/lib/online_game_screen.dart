import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart' hide Card;
import 'package:durak_logic/durak_logic.dart';
import 'card_widget.dart';

// ── Deserialization ───────────────────────────────────────────────────────────

Card _parseCard(Map<String, dynamic> m) => Card(
      Suit.values.byName(m['suit'] as String),
      Rank.values.byName(m['rank'] as String),
    );

Map<String, String> _serCard(Card c) =>
    {'suit': c.suit.name, 'rank': c.rank.name};

// ── Remote state model ────────────────────────────────────────────────────────

class _RemotePlayer {
  final String id;
  final int handSize;
  final bool hasLeft;
  const _RemotePlayer(this.id, this.handSize, this.hasLeft);
}

class _RemoteEntry {
  final Card attack;
  final Card? defense;
  const _RemoteEntry(this.attack, this.defense);
}

class _RemoteGS {
  final GamePhase phase;
  final Suit trump;
  final int deckSize;
  final int discardSize;
  final int attackerIndex;
  final int defenderIndex;
  final List<String> addingPlayerIds;
  final List<Card> hand;
  final List<_RemotePlayer> players;
  final List<_RemoteEntry> table;
  final String? loserId;

  const _RemoteGS({
    required this.phase,
    required this.trump,
    required this.deckSize,
    required this.discardSize,
    required this.attackerIndex,
    required this.defenderIndex,
    required this.addingPlayerIds,
    required this.hand,
    required this.players,
    required this.table,
    this.loserId,
  });

  factory _RemoteGS.fromJson(Map<String, dynamic> m) => _RemoteGS(
        phase: GamePhase.values.byName(m['phase'] as String),
        trump: Suit.values.byName(m['trump'] as String),
        deckSize: m['deckSize'] as int,
        discardSize: m['discardSize'] as int,
        attackerIndex: m['attackerIndex'] as int,
        defenderIndex: m['defenderIndex'] as int,
        addingPlayerIds:
            List<String>.from(m['addingPlayerIds'] as List),
        hand: (m['hand'] as List)
            .map((e) => _parseCard(e as Map<String, dynamic>))
            .toList(),
        players: (m['players'] as List).map((e) {
          final p = e as Map<String, dynamic>;
          return _RemotePlayer(
            p['id'] as String,
            p['handSize'] as int,
            p['hasLeft'] as bool,
          );
        }).toList(),
        table: (m['table'] as List).map((e) {
          final t = e as Map<String, dynamic>;
          return _RemoteEntry(
            _parseCard(t['attack'] as Map<String, dynamic>),
            t['defense'] != null
                ? _parseCard(t['defense'] as Map<String, dynamic>)
                : null,
          );
        }).toList(),
        loserId: m['loserId'] as String?,
      );
}

// ── Widget ────────────────────────────────────────────────────────────────────

class OnlineGameScreen extends StatefulWidget {
  /// Used only for sending messages to the server.
  final WebSocket socket;

  /// Broadcast stream of parsed server messages — created in LobbyScreen.
  final Stream<Map<String, dynamic>> messageStream;

  final String myPlayerId;

  /// First game_state received in the lobby — displayed immediately.
  final Map<String, dynamic>? initialState;

  const OnlineGameScreen({
    super.key,
    required this.socket,
    required this.messageStream,
    required this.myPlayerId,
    this.initialState,
  });

  @override
  State<OnlineGameScreen> createState() => _OnlineGameScreenState();
}

class _OnlineGameScreenState extends State<OnlineGameScreen> {
  StreamSubscription? _sub;
  _RemoteGS? _gs;
  String? _error;

  final Set<int> _selectedHandIndices = {};
  Card? _selectedAttackCard;

  @override
  void initState() {
    super.initState();
    if (widget.initialState != null) {
      _gs = _RemoteGS.fromJson(widget.initialState!);
    }
    _sub = widget.messageStream
        .listen(_onData, onDone: _onDone, onError: _onError);
  }

  @override
  void dispose() {
    _sub?.cancel();
    widget.socket.close();
    super.dispose();
  }

  // ── WebSocket ─────────────────────────────────────────────────────────────

  void _onData(dynamic data) {
    final map = jsonDecode(data as String) as Map<String, dynamic>;
    final type = map['type'] as String;
    if (type == 'game_state') {
      setState(() {
        _gs = _RemoteGS.fromJson(map);
        _selectedHandIndices.clear();
        _selectedAttackCard = null;
        _error = null;
      });
    } else if (type == 'error') {
      setState(() => _error = map['message'] as String);
    }
  }

  void _onDone() {
    if (mounted) setState(() => _error = 'Соединение разорвано');
  }

  void _onError(Object e) {
    if (mounted) setState(() => _error = e.toString());
  }

  void _send(Map<String, dynamic> msg) =>
      widget.socket.add(jsonEncode(msg));

  // ── Helpers ───────────────────────────────────────────────────────────────

  List<Card> get _selectedCards =>
      _selectedHandIndices.map((i) => _gs!.hand[i]).toList();

  bool get _imAttacker =>
      _gs!.players[_gs!.attackerIndex].id == widget.myPlayerId;
  bool get _imDefender =>
      _gs!.players[_gs!.defenderIndex].id == widget.myPlayerId;
  bool get _canAdd =>
      _gs!.addingPlayerIds.contains(widget.myPlayerId);

  // ── Actions ───────────────────────────────────────────────────────────────

  void _doAction(Map<String, dynamic> msg) {
    _send(msg);
    setState(() {
      _selectedHandIndices.clear();
      _selectedAttackCard = null;
    });
  }

  void _attack() => _doAction({
        'type': 'attack',
        'cards': _selectedCards.map(_serCard).toList(),
      });

  void _defend() {
    if (_selectedAttackCard == null || _selectedCards.length != 1) return;
    _doAction({
      'type': 'defend',
      'attackCard': _serCard(_selectedAttackCard!),
      'defenseCard': _serCard(_selectedCards.first),
    });
  }

  void _transfer() => _doAction({
        'type': 'transfer',
        'cards': _selectedCards.map(_serCard).toList(),
      });

  void _transit() {
    if (_selectedCards.length != 1) return;
    _doAction({'type': 'transit', 'card': _serCard(_selectedCards.first)});
  }

  void _addAttack() => _doAction({
        'type': 'add_attack',
        'cards': _selectedCards.map(_serCard).toList(),
      });

  void _pass() => _doAction({'type': 'pass'});

  void _take() => _doAction({'type': 'take'});

  // ── Build ─────────────────────────────────────────────────────────────────

  static const _suitSymbol = {
    Suit.diamonds: '♦',
    Suit.hearts: '♥',
    Suit.clubs: '♣',
    Suit.spades: '♠',
  };
  static const _suitColor = {
    Suit.diamonds: Colors.redAccent,
    Suit.hearts: Colors.redAccent,
    Suit.clubs: Colors.white70,
    Suit.spades: Colors.white70,
  };
  static const _phaseLabel = {
    GamePhase.attacking: 'Атака',
    GamePhase.defending: 'Защита',
    GamePhase.adding: 'Подкидывание',
    GamePhase.taking: 'Добор',
    GamePhase.finished: 'Конец',
  };

  @override
  Widget build(BuildContext context) {
    final gs = _gs;
    if (gs == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Игра')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    if (gs.phase == GamePhase.finished) return _buildGameOver(gs);

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: Row(
          children: [
            Text(
              _suitSymbol[gs.trump]!,
              style: TextStyle(fontSize: 22, color: _suitColor[gs.trump]),
            ),
            const SizedBox(width: 8),
            Text(_phaseLabel[gs.phase]!,
                style: const TextStyle(fontSize: 16)),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                const Icon(Icons.style, size: 16, color: Colors.grey),
                const SizedBox(width: 4),
                Text('${gs.deckSize}',
                    style: const TextStyle(color: Colors.grey)),
              ],
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          if (_error != null) _buildErrorBanner(),
          _buildPlayersRow(gs),
          const Divider(height: 1),
          Expanded(child: _buildTable(gs)),
          const Divider(height: 1),
          _buildHand(gs),
          const Divider(height: 1),
          _buildActions(gs),
        ],
      ),
    );
  }

  Widget _buildErrorBanner() {
    return Material(
      color: Colors.red.shade900,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Row(
          children: [
            const Icon(Icons.error_outline, size: 16, color: Colors.white),
            const SizedBox(width: 8),
            Expanded(
              child: Text(_error!,
                  style: const TextStyle(color: Colors.white, fontSize: 13)),
            ),
            IconButton(
              icon: const Icon(Icons.close, size: 16, color: Colors.white),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              onPressed: () => setState(() => _error = null),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlayersRow(_RemoteGS gs) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          for (int i = 0; i < gs.players.length; i++)
            _buildPlayerChip(gs, i),
        ],
      ),
    );
  }

  Widget _buildPlayerChip(_RemoteGS gs, int i) {
    final p = gs.players[i];
    final isMe = p.id == widget.myPlayerId;
    final isAttacker = i == gs.attackerIndex;
    final isDefender = i == gs.defenderIndex;

    final chipColor = isAttacker
        ? Colors.orange.withAlpha(50)
        : isDefender
            ? Colors.lightBlue.withAlpha(50)
            : null;

    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: chipColor ?? Colors.grey.withAlpha(20),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isMe
                ? Theme.of(context).colorScheme.primary
                : Colors.grey.shade700,
            width: isMe ? 2 : 1,
          ),
        ),
        child: p.hasLeft
            ? const Icon(Icons.exit_to_app, size: 16, color: Colors.grey)
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${i + 1}',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: isMe
                          ? Theme.of(context).colorScheme.primary
                          : null,
                    ),
                  ),
                  const SizedBox(width: 6),
                  const Icon(Icons.style, size: 13, color: Colors.grey),
                  const SizedBox(width: 2),
                  Text('${p.handSize}',
                      style: const TextStyle(fontSize: 13)),
                  if (isAttacker || isDefender) ...[
                    const SizedBox(width: 6),
                    Text(
                      isAttacker ? 'АТК' : 'ЗЩТ',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: isAttacker
                            ? Colors.orange
                            : Colors.lightBlue,
                      ),
                    ),
                  ],
                  if (isMe) ...[
                    const SizedBox(width: 4),
                    Text(
                      '(вы)',
                      style: TextStyle(
                        fontSize: 11,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ],
                ],
              ),
      ),
    );
  }

  Widget _buildTable(_RemoteGS gs) {
    if (gs.table.isEmpty) {
      return const Center(
        child: Text('Стол пуст',
            style: TextStyle(color: Colors.grey, fontSize: 16)),
      );
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Wrap(
        spacing: 16,
        runSpacing: 16,
        children: gs.table.map((e) => _buildTableEntry(e, gs)).toList(),
      ),
    );
  }

  Widget _buildTableEntry(_RemoteEntry entry, _RemoteGS gs) {
    final canSelect =
        _imDefender && gs.phase == GamePhase.defending && entry.defense == null;
    final isSelected = _selectedAttackCard == entry.attack;

    return GestureDetector(
      onTap: canSelect
          ? () => setState(() =>
              _selectedAttackCard = isSelected ? null : entry.attack)
          : null,
      child: SizedBox(
        width: 72,
        height: 96,
        child: Stack(
          children: [
            CardWidget(
              card: entry.attack,
              trump: gs.trump,
              selected: isSelected,
              highlighted: canSelect && !isSelected,
            ),
            if (entry.defense != null)
              Positioned(
                top: 16,
                left: 16,
                child: CardWidget(
                  card: entry.defense!,
                  trump: gs.trump,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildHand(_RemoteGS gs) {
    if (gs.hand.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Center(
          child: Text('Нет карт', style: TextStyle(color: Colors.grey)),
        ),
      );
    }
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          for (int i = 0; i < gs.hand.length; i++)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: CardWidget(
                card: gs.hand[i],
                trump: gs.trump,
                selected: _selectedHandIndices.contains(i),
                onTap: () => setState(() {
                  if (_selectedHandIndices.contains(i)) {
                    _selectedHandIndices.remove(i);
                  } else {
                    _selectedHandIndices.add(i);
                  }
                }),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildActions(_RemoteGS gs) {
    final sel = _selectedCards;
    final hasSel = sel.isNotEmpty;
    final hasSingle = sel.length == 1;
    final hasTarget = _selectedAttackCard != null;
    final phase = gs.phase;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          if (_imAttacker && phase == GamePhase.attacking)
            FilledButton(
              onPressed: hasSel ? _attack : null,
              child: const Text('Атаковать'),
            ),
          if (_imDefender && phase == GamePhase.defending) ...[
            FilledButton(
              onPressed: hasTarget && hasSingle ? _defend : null,
              child: const Text('Отбить'),
            ),
            OutlinedButton(
              onPressed: hasSel ? _transfer : null,
              child: const Text('Перевести'),
            ),
            OutlinedButton(
              onPressed: hasSingle ? _transit : null,
              child: const Text('Проездной'),
            ),
          ],
          if (_imDefender &&
              (phase == GamePhase.defending || phase == GamePhase.adding))
            OutlinedButton(
              onPressed: _take,
              child: const Text('Взять'),
            ),
          if (_canAdd &&
              (phase == GamePhase.adding || phase == GamePhase.taking))
            FilledButton(
              onPressed: hasSel ? _addAttack : null,
              child: const Text('Подкинуть'),
            ),
          if (_canAdd && phase == GamePhase.adding)
            OutlinedButton(
              onPressed: _pass,
              child: const Text('Пас'),
            ),
        ],
      ),
    );
  }

  Widget _buildGameOver(_RemoteGS gs) {
    final loserId = gs.loserId;
    final isLoser = loserId == widget.myPlayerId;
    final isDraw = loserId == null;
    final loserIdx =
        loserId != null ? gs.players.indexWhere((p) => p.id == loserId) : -1;

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text('Конец игры'),
      ),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isDraw
                  ? Icons.handshake
                  : isLoser
                      ? Icons.sentiment_dissatisfied
                      : Icons.emoji_events,
              size: 80,
              color: isDraw
                  ? Colors.grey
                  : isLoser
                      ? Colors.redAccent
                      : Colors.amber,
            ),
            const SizedBox(height: 16),
            Text(
              isDraw
                  ? 'Ничья!'
                  : isLoser
                      ? 'Вы проиграли'
                      : 'Вы победили!',
              style: const TextStyle(
                  fontSize: 28, fontWeight: FontWeight.bold),
            ),
            if (!isDraw && loserIdx >= 0) ...[
              const SizedBox(height: 8),
              Text(
                isLoser
                    ? 'Вы — дурак'
                    : 'Дурак: игрок ${loserIdx + 1}',
                style: const TextStyle(color: Colors.grey, fontSize: 16),
              ),
            ],
            const SizedBox(height: 32),
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('В главное меню'),
            ),
          ],
        ),
      ),
    );
  }
}
