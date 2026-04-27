import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart' hide Card;
import 'package:flutter/services.dart';
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
        addingPlayerIds: List<String>.from(m['addingPlayerIds'] as List),
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
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    if (widget.initialState != null) {
      _gs = _RemoteGS.fromJson(widget.initialState!);
    }
    _sub = widget.messageStream
        .listen(_onData, onDone: _onDone, onError: _onError);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
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
  bool get _canAdd => _gs!.addingPlayerIds.contains(widget.myPlayerId);
  bool get _isTokenHolder =>
      _gs!.players[_gs!.currentAdderIndex].id == widget.myPlayerId;

  int _currentActorIndex(_RemoteGS gs) => switch (gs.phase) {
        GamePhase.attacking => gs.attackerIndex,
        GamePhase.defending => gs.defenderIndex,
        _ => gs.currentAdderIndex,
      };

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
    final cards =
        _selectedCardIds.contains(displayId) && _selectedCardIds.isNotEmpty
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

  // ── Layout constants ──────────────────────────────────────────────────────

  static const double _handHeight = 116.0;

  // ── Seat positions ────────────────────────────────────────────────────────

  static List<Alignment> _seatPositions(int count) => switch (count) {
        2 => const [Alignment(0.00, -0.72)],
        3 => const [Alignment(-0.50, -0.72), Alignment(0.50, -0.72)],
        4 => const [
            Alignment(-0.88, 0.15),
            Alignment(0.00, -0.72),
            Alignment(0.88, 0.15),
          ],
        5 => const [
            Alignment(-0.88, 0.15),
            Alignment(-0.45, -0.72),
            Alignment(0.45, -0.72),
            Alignment(0.88, 0.15),
          ],
        6 => const [
            Alignment(-0.88, 0.15),
            Alignment(-0.55, -0.72),
            Alignment(0.00, -0.72),
            Alignment(0.55, -0.72),
            Alignment(0.88, 0.15),
          ],
        _ => const [],
      };

  static EdgeInsets _tablePadding(int playerCount) =>
      playerCount <= 3
          ? const EdgeInsets.fromLTRB(8, 140, 8, 8)
          : const EdgeInsets.fromLTRB(80, 140, 80, 8);

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final gs = _gs;
    if (gs == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    if (gs.phase == GamePhase.finished) return _buildGameOver(gs);

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            if (_error != null) _buildErrorBanner(),
            _buildStatusBar(gs),
            Expanded(child: _buildTableArea(gs)),
            _buildActionsBar(gs),
            SizedBox(height: _handHeight, child: _buildHand(gs)),
          ],
        ),
      ),
    );
  }

  // ── Table area ────────────────────────────────────────────────────────────

  Widget _buildTableArea(_RemoteGS gs) {
    final myIndex = gs.players.indexWhere((p) => p.id == widget.myPlayerId);
    final count = gs.players.length;
    final positions = _seatPositions(count);

    return Stack(
      children: [
        Positioned.fill(
          child: Padding(
            padding: _tablePadding(count),
            child: _buildTableGrid(gs),
          ),
        ),
        for (int si = 1; si < count; si++)
          Align(
            alignment: positions[si - 1],
            child: _buildPlayerSeat(gs, (myIndex + si) % count),
          ),
        Positioned(
          right: 8,
          bottom: 8,
          child: _buildFab(gs) ?? const SizedBox.shrink(),
        ),
      ],
    );
  }

  // ── PlayerSeat ────────────────────────────────────────────────────────────

  Widget _buildPlayerSeat(_RemoteGS gs, int playerIndex) {
    final p = gs.players[playerIndex];
    final isActor = playerIndex == _currentActorIndex(gs);
    final isDefender = playerIndex == gs.defenderIndex;

    final borderColor = isActor
        ? (isDefender ? Colors.lightBlue : Colors.orange)
        : Colors.grey.shade700;
    final borderWidth = isActor ? 2.5 : 1.0;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
      constraints: const BoxConstraints(maxWidth: 96),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: borderColor, width: borderWidth),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildCardFan(p.handSize),
          const SizedBox(height: 3),
          Text(
            p.hasLeft ? '—' : (p.nickname.isEmpty ? '?' : p.nickname),
            style: const TextStyle(fontSize: 10, color: Colors.white70),
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.style, size: 9, color: Colors.grey),
              const SizedBox(width: 2),
              Text(
                '${p.handSize}',
                style: const TextStyle(fontSize: 10, color: Colors.grey),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCardFan(int count) {
    final shown = count.clamp(0, 5);
    if (shown == 0) {
      return const SizedBox(width: kCardWidth, height: kCardHeight);
    }
    const step = 8.0;
    return SizedBox(
      width: kCardWidth + (shown - 1) * step,
      height: kCardHeight,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          for (int i = 0; i < shown; i++)
            Positioned(
              left: i * step,
              child: Transform.rotate(
                angle: (i - (shown - 1) / 2) * 0.12,
                child: const CardWidget(faceUp: false, width: kCardWidth),
              ),
            ),
        ],
      ),
    );
  }

  // ── Status bar ────────────────────────────────────────────────────────────

  String _playerName(_RemoteGS gs, int index) {
    final p = gs.players[index];
    return p.nickname.isEmpty ? 'Игрок ${index + 1}' : p.nickname;
  }

  Widget _buildStatusBar(_RemoteGS gs) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildDeckStatus(gs),
          Expanded(child: _buildStatusText(gs)),
          _buildDiscardStatus(gs),
        ],
      ),
    );
  }

  Widget _buildDeckStatus(_RemoteGS gs) {
    if (gs.deckSize == 0) return SizedBox(width: kCardWidth);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: kCardWidth,
          height: kCardHeight,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              if (gs.trumpCard != null)
                Positioned(
                  left: kCardWidth / 2,
                  top: (kCardHeight - kCardWidth) / 2,
                  child: RotatedBox(
                    quarterTurns: 1,
                    child: CardWidget(
                      card: gs.trumpCard,
                      faceUp: true,
                      width: kCardWidth,
                    ),
                  ),
                ),
              const CardWidget(faceUp: false, width: kCardWidth),
            ],
          ),
        ),
        const SizedBox(height: 3),
        Text(
          '${gs.deckSize}',
          style: const TextStyle(color: Colors.grey, fontSize: 11),
        ),
      ],
    );
  }

  Widget _buildDiscardStatus(_RemoteGS gs) {
    if (gs.discardSize == 0) return SizedBox(width: kCardWidth);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Transform.rotate(
          angle: 0.12,
          child: const CardWidget(faceUp: false, width: kCardWidth),
        ),
        const SizedBox(height: 3),
        Text(
          '${gs.discardSize}',
          style: const TextStyle(color: Colors.grey, fontSize: 11),
        ),
      ],
    );
  }

  Widget _buildStatusText(_RemoteGS gs) {
    final (line1, line2) = switch (gs.phase) {
      GamePhase.attacking => (
          '${_playerName(gs, gs.attackerIndex)} ходит',
          'под ${_playerName(gs, gs.defenderIndex)}',
        ),
      GamePhase.defending => (
          '${_playerName(gs, gs.defenderIndex)} отбивается',
          '',
        ),
      GamePhase.adding => (
          '${_playerName(gs, gs.currentAdderIndex)} подкидывает',
          'под ${_playerName(gs, gs.defenderIndex)}',
        ),
      GamePhase.taking => (
          '${_playerName(gs, gs.defenderIndex)} берёт',
          '',
        ),
      _ => ('', ''),
    };
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          line1,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 13, color: Colors.white),
        ),
        if (line2.isNotEmpty)
          Text(
            line2,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12, color: Colors.white60),
          ),
      ],
    );
  }

  // ── Error banner ──────────────────────────────────────────────────────────

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

  // ── Table grid ────────────────────────────────────────────────────────────

  Widget _buildTableGrid(_RemoteGS gs) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (int row = 0; row < 3; row++)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (int col = 0; col < 3; col++)
                  Padding(
                    padding: const EdgeInsets.all(4),
                    child: SizedBox(
                      width: 72,
                      height: 96,
                      child: _tableCell(gs, row * 3 + col),
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _tableCell(_RemoteGS gs, int i) => i < gs.table.length
      ? _buildTableEntry(gs.table[i], gs)
      : _buildEmptyTableCell(gs);

  Widget _buildEmptyTableCell(_RemoteGS gs) {
    final isTransfer = _imDefender && gs.phase == GamePhase.defending;
    final canDrop = isTransfer ||
        (_imAttacker && gs.phase == GamePhase.attacking) ||
        (_canAdd &&
            (gs.phase == GamePhase.adding || gs.phase == GamePhase.taking));

    return DragTarget<int>(
      onWillAcceptWithDetails: (_) => canDrop,
      onAcceptWithDetails: (d) => isTransfer
          ? _transferByDrag(gs, d.data)
          : _attackByDrag(gs, d.data),
      builder: (context, candidateData, _) {
        final hovering = candidateData.isNotEmpty;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          decoration: BoxDecoration(
            border: Border.all(
              color: hovering ? Colors.orange.withAlpha(160) : Colors.white12,
              width: hovering ? 2 : 1,
            ),
            borderRadius: BorderRadius.circular(6),
          ),
          child: hovering
              ? Center(
                  child: Text(
                    isTransfer ? 'Перевести' : 'Бросить',
                    style: const TextStyle(color: Colors.orange, fontSize: 11),
                  ),
                )
              : null,
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

  // ── Hand ──────────────────────────────────────────────────────────────────

  Widget _buildHand(_RemoteGS gs) {
    if (gs.hand.isEmpty) {
      return const Center(
        child: Text('Нет карт', style: TextStyle(color: Colors.grey)),
      );
    }
    final sorted = sortHand(gs.hand, gs.trump);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: Row(
        children: [
          for (final card in sorted)
            Padding(
              padding: const EdgeInsets.only(right: 6),
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

  // ── Actions bar ───────────────────────────────────────────────────────────

  Widget _buildActionsBar(_RemoteGS gs) {
    final sel = _selectedCards;
    final hasSel = sel.isNotEmpty;
    final hasSingle = sel.length == 1;
    final hasTarget = _selectedAttackCard != null;
    final phase = gs.phase;

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
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
          ],
          if (phase == GamePhase.adding || phase == GamePhase.taking)
            FilledButton(
              onPressed: _canAdd && hasSel ? _addAttack : null,
              child: const Text('Подкинуть'),
            ),
        ],
      ),
    );
  }

  // ── FAB: Take / Pass ──────────────────────────────────────────────────────

  Widget? _buildFab(_RemoteGS gs) {
    final phase = gs.phase;
    if (_imDefender &&
        (phase == GamePhase.defending || phase == GamePhase.adding)) {
      return FloatingActionButton.extended(
        heroTag: 'take_fab',
        onPressed: _take,
        label: const Text('Взять'),
        icon: const Icon(Icons.download_rounded, size: 18),
        backgroundColor: Colors.red.shade700,
      );
    }
    if (_isTokenHolder &&
        (phase == GamePhase.adding || phase == GamePhase.taking)) {
      return FloatingActionButton.extended(
        heroTag: 'pass_fab',
        onPressed: _pass,
        label: const Text('Пас'),
        icon: const Icon(Icons.skip_next_rounded, size: 18),
      );
    }
    return null;
  }

  // ── Game over ─────────────────────────────────────────────────────────────

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
              style:
                  const TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
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
