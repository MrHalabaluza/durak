import 'package:flutter/material.dart' hide Card;
import 'package:durak_logic/durak_logic.dart';
import 'card_widget.dart';

class GameScreen extends StatefulWidget {
  final int playerCount;
  final DeckConfig deckConfig;
  const GameScreen({
    super.key,
    required this.playerCount,
    required this.deckConfig,
  });

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  late Game _game;

  Set<Card> _selectedCards = {};
  Card? _selectedAttackTarget;
  String? _lastError;

  @override
  void initState() {
    super.initState();
    _startGame();
  }

  void _startGame() {
    final ids = List.generate(widget.playerCount, (i) => 'Игрок ${i + 1}');
    _game = Game.start(ids, config: widget.deckConfig);
    _selectedCards = {};
    _selectedAttackTarget = null;
    _lastError = null;
  }

  GameState get gs => _game.state;

  void _doAction(void Function() action) {
    setState(() {
      try {
        action();
        _lastError = null;
        _selectedCards = {};
        _selectedAttackTarget = null;
      } on GameException catch (e) {
        _lastError = e.message;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('DTFool'),
        actions: [
          TextButton.icon(
            icon: const Icon(Icons.refresh),
            label: const Text('Новая игра'),
            onPressed: () => setState(_startGame),
          ),
        ],
      ),
      body: gs.phase == GamePhase.finished ? _buildFinished() : _buildGame(),
    );
  }

  Widget _buildFinished() {
    final loserId = gs.loserId;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            loserId == null ? 'Ничья!' : '$loserId — дурак!',
            style: const TextStyle(fontSize: 36, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: () => setState(_startGame),
            child: const Text('Сыграть снова'),
          ),
        ],
      ),
    );
  }

  Widget _buildGame() {
    return Column(
      children: [
        _buildStatusBar(),
        if (_lastError != null)
          Container(
            color: Colors.red.shade900,
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Text(_lastError!, style: const TextStyle(color: Colors.white)),
          ),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(width: 300, child: _buildPlayersPanel()),
              const VerticalDivider(width: 1),
              Expanded(child: _buildTablePanel()),
              const VerticalDivider(width: 1),
              SizedBox(width: 220, child: _buildActionsPanel()),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStatusBar() {
    return Container(
      color: Colors.green.shade900,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        children: [
          Text('Козырь: ${_suitName(gs.trump)}',
              style: const TextStyle(fontSize: 15)),
          const SizedBox(width: 24),
          Text('Колода: ${gs.deck.size}',
              style: const TextStyle(fontSize: 15)),
          const SizedBox(width: 24),
          Text('Фаза: ${_phaseName(gs.phase)}',
              style: const TextStyle(fontSize: 15)),
          const Spacer(),
          Text(
            'Ходит: ${gs.attacker.id}   Отбивает: ${gs.defender.id}',
            style: const TextStyle(fontSize: 15),
          ),
        ],
      ),
    );
  }

  Widget _buildPlayersPanel() {
    return ListView(
      padding: const EdgeInsets.all(8),
      children: [
        const Text('Игроки',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        for (final player in gs.players) _buildPlayerHand(player),
      ],
    );
  }

  Widget _buildPlayerHand(Player player) {
    final isTokenHolder = player.id == gs.players[gs.currentAdderIndex].id;
    final isDefender = player.id == gs.defender.id;

    String role = '';
    if (player.hasLeft) {
      role = ' ✓ вышел';
    } else if (isTokenHolder) {
      role = ' ⚔ ходит';
    } else if (isDefender) {
      role = ' 🛡 отбивает';
    }

    Color? bgColor;
    if (player.hasLeft) {
      bgColor = Colors.grey.shade800;
    } else if (isTokenHolder) {
      bgColor = Colors.orange.shade900;
    } else if (isDefender) {
      bgColor = Colors.blue.shade900;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: bgColor ?? Colors.grey.shade900,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade700),
      ),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${player.id}$role (${player.handSize})',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            if (player.hasCards)
              Wrap(
                spacing: 4,
                runSpacing: 4,
                children: [
                  for (final card in player.hand)
                    CardWidget(
                      card: card,
                      trump: gs.trump,
                      selected: _selectedCards.contains(card),
                      onTap: () => _onCardTap(card),
                    ),
                ],
              )
            else
              const Text('Нет карт', style: TextStyle(color: Colors.grey)),
          ],
        ),
      ),
    );
  }

  Widget _buildTablePanel() {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Стол',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          if (gs.table.isEmpty)
            const Text('Стол пуст', style: TextStyle(color: Colors.grey))
          else
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final entry in gs.table.entries)
                  _buildTableEntry(entry),
              ],
            ),
          const Spacer(),
          Text(
            'В отбое: ${gs.discard.length} карт',
            style: const TextStyle(color: Colors.grey),
          ),
        ],
      ),
    );
  }

  Widget _buildTableEntry(TableEntry entry) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        CardWidget(
          card: entry.attack,
          trump: gs.trump,
          highlighted: entry.attack == _selectedAttackTarget,
          onTap: () => _onTableAttackTap(entry.attack),
        ),
        const SizedBox(height: 4),
        if (entry.defense != null)
          CardWidget(card: entry.defense!, trump: gs.trump)
        else
          Container(
            width: 56,
            height: 80,
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey),
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Icon(Icons.add, color: Colors.grey),
          ),
      ],
    );
  }

  Widget _buildActionsPanel() {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Действия',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          if (_selectedCards.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                'Выбрано: ${_selectedCards.map(_cardName).join(', ')}',
                style: const TextStyle(color: Colors.yellow),
              ),
            ),
          if (_selectedAttackTarget != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                'Цель: ${_cardName(_selectedAttackTarget!)}',
                style: const TextStyle(color: Colors.lightBlue),
              ),
            ),
          const Divider(),
          if (gs.phase == GamePhase.attacking)
            _actionBtn('⚔ Атаковать', _selectedCards.isNotEmpty, _doAttack),
          if (gs.phase == GamePhase.defending) ...[
            _actionBtn(
              '🛡 Отбить',
              _selectedCards.length == 1 && _selectedAttackTarget != null,
              _doDefend,
            ),
            _actionBtn('↪ Перевести', _selectedCards.isNotEmpty, _doTransfer),
            _actionBtn('✋ Взять', true, _doTake),
          ],
          if (gs.phase == GamePhase.adding) ...[
            _actionBtn('➕ Подкинуть', _selectedCards.isNotEmpty, _doAdd),
            _actionBtn('⏭ Пас', true, _doPass),
          ],
          const Divider(),
          _actionBtn(
            '✘ Снять выбор',
            _selectedCards.isNotEmpty || _selectedAttackTarget != null,
            () => setState(() {
              _selectedCards = {};
              _selectedAttackTarget = null;
            }),
          ),
          const Spacer(),
          const Text(
            'Как пользоваться:\n'
            '1. Нажми карту в руке → выбрать\n'
            '2. Для отбоя: нажми атакующую карту на столе → цель\n'
            '3. Нажми действие',
            style: TextStyle(fontSize: 11, color: Colors.grey),
          ),
        ],
      ),
    );
  }

  Widget _actionBtn(String label, bool enabled, VoidCallback onPressed) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: ElevatedButton(
        onPressed: enabled ? onPressed : null,
        child: Text(label),
      ),
    );
  }

  // ── Tap handlers ─────────────────────────────────────────────────────────────

  void _onCardTap(Card card) {
    setState(() {
      _lastError = null;
      if (_selectedCards.contains(card)) {
        _selectedCards = Set.from(_selectedCards)..remove(card);
      } else if (_selectedCards.isEmpty ||
          _selectedCards.first.rank == card.rank) {
        _selectedCards = Set.from(_selectedCards)..add(card);
      } else {
        // Different rank — start fresh selection.
        _selectedCards = {card};
      }
    });
  }

  void _onTableAttackTap(Card attackCard) {
    setState(() {
      _lastError = null;
      _selectedAttackTarget =
          _selectedAttackTarget == attackCard ? null : attackCard;
    });
  }

  // ── Game actions ─────────────────────────────────────────────────────────────

  void _doAttack() {
    if (_selectedCards.isEmpty) return;
    _doAction(() => _game.attack(gs.attacker.id, _selectedCards.toList()));
  }

  void _doDefend() {
    if (_selectedCards.length != 1 || _selectedAttackTarget == null) return;
    _doAction(() => _game.defend(
        gs.defender.id, _selectedAttackTarget!, _selectedCards.first));
  }

  void _doTransfer() {
    if (_selectedCards.isEmpty) return;
    _doAction(() => _game.transfer(gs.defender.id, _selectedCards.toList()));
  }

  void _doAdd() {
    if (_selectedCards.isEmpty) return;
    _doAction(() => _game.addAttack(
        gs.players[gs.currentAdderIndex].id, _selectedCards.toList()));
  }

  void _doPass() {
    _doAction(() => _game.pass(gs.players[gs.currentAdderIndex].id));
  }

  void _doTake() {
    _doAction(() => _game.take(gs.defender.id));
  }

  // ── Formatters ────────────────────────────────────────────────────────────────

  String _suitName(Suit s) => switch (s) {
        Suit.diamonds => '♦ Бубны',
        Suit.hearts => '♥ Черви',
        Suit.clubs => '♣ Крести',
        Suit.spades => '♠ Пики',
      };

  String _phaseName(GamePhase p) => switch (p) {
        GamePhase.attacking => 'Атака',
        GamePhase.defending => 'Защита',
        GamePhase.adding => 'Подкидывание',
        GamePhase.finished => 'Конец',
      };

  String _cardName(Card c) {
    final rank = switch (c.rank) {
      Rank.two => '2',
      Rank.three => '3',
      Rank.four => '4',
      Rank.five => '5',
      Rank.six => '6',
      Rank.seven => '7',
      Rank.eight => '8',
      Rank.nine => '9',
      Rank.ten => '10',
      Rank.jack => 'В',
      Rank.queen => 'Д',
      Rank.king => 'К',
      Rank.ace => 'Т',
    };
    final suit = switch (c.suit) {
      Suit.diamonds => '♦',
      Suit.hearts => '♥',
      Suit.clubs => '♣',
      Suit.spades => '♠',
    };
    return '$rank$suit';
  }
}
