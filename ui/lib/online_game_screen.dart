import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart' hide Card;
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:durak_logic/durak_logic.dart';
import 'card_widget.dart';
import 'sort_hand.dart';

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
  final String nickname;
  final int handSize;
  final bool hasLeft;
  const _RemotePlayer(this.id, this.nickname, this.handSize, this.hasLeft);
}

class _RemoteEntry {
  final Card attack;
  final Card? defense;
  const _RemoteEntry(this.attack, this.defense);
}

class _RemoteGS {
  final GamePhase phase;
  final Suit trump;
  final Card? trumpCard;
  final int deckSize;
  final int discardSize;
  final int attackerIndex;
  final int defenderIndex;
  final int currentAdderIndex;
  final List<String> addingPlayerIds;
  final List<Card> hand;
  final List<_RemotePlayer> players;
  final List<_RemoteEntry> table;
  final String? loserId;

  const _RemoteGS({
    required this.phase,
    required this.trump,
    this.trumpCard,
    required this.deckSize,
    required this.discardSize,
    required this.attackerIndex,
    required this.defenderIndex,
    required this.currentAdderIndex,
    required this.addingPlayerIds,
    required this.hand,
    required this.players,
    required this.table,
    this.loserId,
  });

  factory _RemoteGS.fromJson(Map<String, dynamic> m) => _RemoteGS(
        phase: GamePhase.values.byName(m['phase'] as String),
        trump: Suit.values.byName(m['trump'] as String),
        trumpCard: m['trumpCard'] != null
            ? _parseCard(m['trumpCard'] as Map<String, dynamic>)
            : null,
        deckSize: m['deckSize'] as int,
        discardSize: m['discardSize'] as int,
        attackerIndex: m['attackerIndex'] as int,
        defenderIndex: m['defenderIndex'] as int,
        currentAdderIndex: m['currentAdderIndex'] as int,
        addingPlayerIds:
            List<String>.from(m['addingPlayerIds'] as List),
        hand: (m['hand'] as List)
            .map((e) => _parseCard(e as Map<String, dynamic>))
            .toList(),
        players: (m['players'] as List).map((e) {
          final p = e as Map<String, dynamic>;
          return _RemotePlayer(
            p['id'] as String,
            p['nickname'] as String? ?? '',
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
  final WebSocketChannel socket;

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

class _OnlineGameScreenState extends State<OnlineGameScreen>
    with WidgetsBindingObserver {
  StreamSubscription? _sub;
  _RemoteGS? _gs;
  String? _error;

  final Set<int> _selectedCardIds = {};
  Card? _selectedAttackCard;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (widget.initialState != null) {
      _gs = _RemoteGS.fromJson(widget.initialState!);
    }
    _sub = widget.messageStream
        .listen(_onData, onDone: _onDone, onError: _onError);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _sub?.cancel();
    widget.socket.sink.close();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      setState(() {});
    }
  }

  // ── WebSocket ─────────────────────────────────────────────────────────────

  void _onData(Map<String, dynamic> map) {
    final type = map['type'] as String;
    if (type == 'game_state') {
      setState(() {
        _gs = _RemoteGS.fromJson(map);
        _selectedCardIds.clear();
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
      widget.socket.sink.add(jsonEncode(msg));

  // ── Helpers ───────────────────────────────────────────────────────────────

  List<Card> get _selectedCards => _gs!.hand
      .where((c) => _selectedCardIds.contains(cardDisplayId(c)))
      .toList();

  bool get _imAttacker =>
      _gs!.players[_gs!.attackerIndex].id == widget.myPlayerId;
  bool get _imDefender =>
      _gs!.players[_gs!.defenderIndex].id == widget.myPlayerId;
  bool get _canAdd =>
      _gs!.addingPlayerIds.contains(widget.myPlayerId);
  bool get _isTokenHolder =>
      _gs!.players[_gs!.currentAdderIndex].id == widget.myPlayerId;

  // ── Actions ───────────────────────────────────────────────────────────────

  void _doAction(Map<String, dynamic> msg) {
    _send(msg);
    setState(() {
      _selectedCardIds.clear();
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

  Card? _cardByDisplayId(_RemoteGS gs, int displayId) =>
      gs.hand.where((c) => cardDisplayId(c) == displayId).firstOrNull;

  void _attackByDrag(_RemoteGS gs, int displayId) {
    final dragged = _cardByDisplayId(gs, displayId);
    if (dragged == null) return;
    final cards = _selectedCardIds.contains(displayId) && _selectedCardIds.isNotEmpty
        ? _selectedCards
        : [dragged];
    final isAdding =
        gs.phase == GamePhase.adding || gs.phase == GamePhase.taking;
    _doAction({
      'type': isAdding ? 'add_attack' : 'attack',
      'cards': cards.map(_serCard).toList(),
    });
  }

  void _defendByDrag(Card attackCard, int displayId) {
    final defense = _cardByDisplayId(_gs!, displayId);
    if (defense == null) return;
    _doAction({
      'type': 'defend',
      'attackCard': _serCard(attackCard),
      'defenseCard': _serCard(defense),
    });
  }

  void _transferByDrag(_RemoteGS gs, int displayId) {
    final dragged = _cardByDisplayId(gs, displayId);
    if (dragged == null) return;
    final cards = _selectedCardIds.contains(displayId) && _selectedCardIds.isNotEmpty
        ? _selectedCards
        : [dragged];
    _doAction({
      'type': 'transfer',
      'cards': cards.map(_serCard).toList(),
    });
  }

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
      ),
      body: Column(
        children: [
          if (_error != null) _buildErrorBanner(),
          _buildPlayersRow(gs),
          const Divider(height: 1),
          _buildCornersRow(gs),
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

  // ── Deck / discard corners ────────────────────────────────────────────────

  static const double _cw = 42.0;
  static const double _ch = _cw * kCardHeight / kCardWidth;

  Widget _buildCornersRow(_RemoteGS gs) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        children: [
          if (gs.deckSize > 0) _buildDeckCorner(gs),
          const Spacer(),
          if (gs.discardSize > 0) _buildDiscardCorner(gs),
        ],
      ),
    );
  }

  Widget _buildDeckCorner(_RemoteGS gs) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Deck card with trump peeking out to the right (Clip.none, so trump
        // protrudes into the Spacer without shifting layout).
        SizedBox(
          width: _cw,
          height: _ch,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              if (gs.trumpCard != null)
                Positioned(
                  left: _cw / 2,
                  top: (_ch - _cw) / 2,
                  child: RotatedBox(
                    quarterTurns: 1,
                    child: CardWidget(
                      card: gs.trumpCard,
                      faceUp: true,
                      width: _cw,
                    ),
                  ),
                ),
              CardWidget(faceUp: false, width: _cw),
            ],
          ),
        ),
        const SizedBox(width: 6),
        Text('${gs.deckSize}',
            style: const TextStyle(color: Colors.grey, fontSize: 13)),
      ],
    );
  }

  Widget _buildDiscardCorner(_RemoteGS gs) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text('${gs.discardSize}',
            style: const TextStyle(color: Colors.grey, fontSize: 13)),
        const SizedBox(width: 6),
        Transform.rotate(
          angle: 0.12,
          child: const CardWidget(faceUp: false, width: _cw),
        ),
      ],
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

  /// Index of the player who must act next (place a card or pass).
  int _currentActorIndex(_RemoteGS gs) => switch (gs.phase) {
        GamePhase.attacking => gs.attackerIndex,
        GamePhase.defending => gs.defenderIndex,
        _ => gs.currentAdderIndex,
      };

  Widget _buildPlayerChip(_RemoteGS gs, int i) {
    final p = gs.players[i];
    final isMe = p.id == widget.myPlayerId;
    final isAdder = gs.addingPlayerIds.contains(p.id);
    final isDefender = i == gs.defenderIndex;
    final isActor = i == _currentActorIndex(gs);

    final bgColor = isDefender
        ? Colors.lightBlue.withAlpha(50)
        : isAdder
            ? Colors.orange.withAlpha(50)
            : Colors.grey.withAlpha(20);

    final borderColor = isActor
        ? (isDefender ? Colors.lightBlue : Colors.orange)
        : isMe
            ? Theme.of(context).colorScheme.primary
            : Colors.grey.shade700;
    final borderWidth = isActor ? 2.5 : 1.0;

    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: borderColor, width: borderWidth),
        ),
        child: p.hasLeft
            ? const Icon(Icons.exit_to_app, size: 16, color: Colors.grey)
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    p.nickname.isEmpty ? '${i + 1}' : p.nickname,
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
                  if (isAdder || isDefender) ...[
                    const SizedBox(width: 6),
                    Text(
                      isDefender ? 'ЗЩТ' : 'АТК',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: isDefender
                            ? Colors.lightBlue
                            : Colors.orange,
                      ),
                    ),
                  ],
                ],
              ),
      ),
    );
  }

  Widget _buildTable(_RemoteGS gs) {
    final isTransferDrop = _imDefender && gs.phase == GamePhase.defending;
    final canDrop = isTransferDrop ||
        (_imAttacker && gs.phase == GamePhase.attacking) ||
        (_canAdd &&
            (gs.phase == GamePhase.adding || gs.phase == GamePhase.taking));

    return DragTarget<int>(
      onWillAcceptWithDetails: (_) => canDrop,
      onAcceptWithDetails: (d) => isTransferDrop
          ? _transferByDrag(gs, d.data)
          : _attackByDrag(gs, d.data),
      builder: (context, candidateData, _) {
        final hovering = candidateData.isNotEmpty;
        final hoverColor = isTransferDrop ? Colors.lightBlue : Colors.orange;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          decoration: hovering
              ? BoxDecoration(
                  border: Border.all(color: hoverColor.withAlpha(160), width: 2),
                  borderRadius: BorderRadius.circular(8),
                )
              : null,
          child: gs.table.isEmpty
              ? Center(
                  child: Text(
                    hovering
                        ? (isTransferDrop ? 'Перевести' : 'Бросить карту')
                        : 'Стол пуст',
                    style: TextStyle(
                      color: hovering ? hoverColor : Colors.grey,
                      fontSize: 16,
                    ),
                  ),
                )
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Wrap(
                    spacing: 16,
                    runSpacing: 16,
                    children:
                        gs.table.map((e) => _buildTableEntry(e, gs)).toList(),
                  ),
                ),
        );
      },
    );
  }

  Widget _buildTableEntry(_RemoteEntry entry, _RemoteGS gs) {
    final canDefend =
        _imDefender && gs.phase == GamePhase.defending && entry.defense == null;
    final isSelected = _selectedAttackCard == entry.attack;

    return DragTarget<int>(
      onWillAcceptWithDetails: (_) => canDefend,
      onAcceptWithDetails: (d) => _defendByDrag(entry.attack, d.data),
      builder: (context, candidateData, _) {
        final hovering = candidateData.isNotEmpty;
        return GestureDetector(
          onTap: canDefend
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
                  selected: isSelected || hovering,
                  highlighted: canDefend && !isSelected && !hovering,
                ),
                if (entry.defense != null)
                  Positioned(
                    top: 16,
                    left: 16,
                    child: CardWidget(card: entry.defense!),
                  ),
              ],
            ),
          ),
        );
      },
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
    final sorted = sortHand(gs.hand, gs.trump);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          for (final card in sorted)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Draggable<int>(
                data: cardDisplayId(card),
                feedback: Material(
                  color: Colors.transparent,
                  child: Transform.scale(
                    scale: 1.1,
                    child: CardWidget(card: card, selected: true),
                  ),
                ),
                childWhenDragging: Opacity(
                  opacity: 0.35,
                  child: CardWidget(card: card),
                ),
                child: CardWidget(
                  card: card,
                  selected: _selectedCardIds.contains(cardDisplayId(card)),
                  onTap: () => setState(() {
                    final id = cardDisplayId(card);
                    if (_selectedCardIds.contains(id)) {
                      _selectedCardIds.remove(id);
                    } else {
                      _selectedCardIds.add(id);
                    }
                  }),
                ),
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
          if (phase == GamePhase.attacking)
            FilledButton(
              onPressed: _imAttacker && hasSel ? _attack : null,
              child: const Text('Атаковать'),
            ),
          if (phase == GamePhase.defending) ...[
            FilledButton(
              onPressed: _imDefender && hasTarget && hasSingle ? _defend : null,
              child: const Text('Отбить'),
            ),
            OutlinedButton(
              onPressed: _imDefender && hasSel ? _transfer : null,
              child: const Text('Перевести'),
            ),
            OutlinedButton(
              onPressed: _imDefender && hasSingle ? _transit : null,
              child: const Text('Проездной'),
            ),
            OutlinedButton(
              onPressed: _imDefender ? _take : null,
              child: const Text('Взять'),
            ),
          ],
          if (phase == GamePhase.adding) ...[
            FilledButton(
              onPressed: _canAdd && hasSel ? _addAttack : null,
              child: const Text('Подкинуть'),
            ),
            OutlinedButton(
              onPressed: _imDefender ? _take : null,
              child: const Text('Взять'),
            ),
            OutlinedButton(
              onPressed: _isTokenHolder ? _pass : null,
              child: const Text('Пас'),
            ),
          ],
          if (phase == GamePhase.taking) ...[
            FilledButton(
              onPressed: _canAdd && hasSel ? _addAttack : null,
              child: const Text('Подкинуть'),
            ),
            OutlinedButton(
              onPressed: _isTokenHolder ? _pass : null,
              child: const Text('Пас'),
            ),
          ],
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
                    : 'Дурак: ${gs.players[loserIdx].nickname.isEmpty ? 'игрок ${loserIdx + 1}' : gs.players[loserIdx].nickname}',
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
