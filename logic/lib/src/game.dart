import 'dart:math';
import 'card.dart';
import 'deck.dart';
import 'player.dart';
import 'game_state.dart';

class GameException implements Exception {
  final String message;
  const GameException(this.message);

  @override
  String toString() => 'GameException: $message';
}

class Game {
  static const int _initialDeal = 9;
  static const int _replenishTo = 6;
  static const int _maxTableCards = 9;

  final GameState state;

  Game._(this.state);

  // ── Factory ─────────────────────────────────────────────────────────────────

  factory Game.start(List<String> playerIds, {Random? random}) {
    if (playerIds.length < 2 || playerIds.length > 6) {
      throw const GameException('Player count must be 2–6');
    }
    final rng = random ?? Random();
    final deck = Deck.standard();
    deck.shuffle(rng);

    final players = playerIds.map(Player.new).toList();
    for (final p in players) {
      p.addCards(deck.drawMany(_initialDeal));
    }

    final trumpCard = deck.topCard;
    if (trumpCard == null) throw const GameException('Not enough cards in deck');
    final trump = trumpCard.suit;

    final firstIdx = _firstPlayerIndex(players, trump, rng);
    final defIdx = (firstIdx + 1) % players.length;

    return Game._(GameState(
      players: players,
      trump: trump,
      deck: deck,
      attackerIndex: firstIdx,
      defenderIndex: defIdx,
    ));
  }

  /// Player with the lowest-ranked trump goes first.
  static int _firstPlayerIndex(
      List<Player> players, Suit trump, Random rng) {
    Rank? bestRank;
    final candidates = <int>[];

    for (var i = 0; i < players.length; i++) {
      final trumpCards = players[i].hand.where((c) => c.suit == trump);
      if (trumpCards.isEmpty) continue;
      final minRank =
          trumpCards.map((c) => c.rank).reduce((a, b) => a.index <= b.index ? a : b);

      if (bestRank == null || minRank.index < bestRank.index) {
        bestRank = minRank;
        candidates
          ..clear()
          ..add(i);
      } else if (minRank == bestRank) {
        candidates.add(i);
      }
    }

    if (candidates.isEmpty) return rng.nextInt(players.length);
    if (candidates.length == 1) return candidates.first;
    return candidates[rng.nextInt(candidates.length)];
  }

  // ── Helpers ──────────────────────────────────────────────────────────────────

  Player _requirePlayer(String id) => state.players.firstWhere(
        (p) => p.id == id,
        orElse: () => throw GameException('Unknown player: $id'),
      );

  void _require(bool condition, String message) {
    if (!condition) throw GameException(message);
  }

  /// The IDs of players who may add cards and must pass to end the turn:
  /// the attacker and the player immediately clockwise of the defender.
  Set<String> _addingPlayerIds() {
    final ids = <String>{state.attacker.id};
    final nextIdx = state.nextActiveIndex(state.defenderIndex);
    ids.add(state.players[nextIdx].id);
    ids.remove(state.defender.id);
    return ids;
  }

  Set<String> get addingPlayerIds => _addingPlayerIds();

  // ── Public actions ────────────────────────────────────────────────────────────

  /// Attacker plays initial cards — all must share a rank.
  void attack(String playerId, List<Card> cards) {
    _require(state.phase == GamePhase.attacking, 'Not in attacking phase');
    _require(playerId == state.attacker.id, 'Not your turn to attack');
    _require(cards.isNotEmpty, 'Must play at least one card');
    _require(cards.length <= _maxTableCards, 'Too many cards');
    _require(
      cards.map((c) => c.rank).toSet().length == 1,
      'All attacking cards must share a rank',
    );
    final player = _requirePlayer(playerId);
    _require(player.hasAllCards(cards), 'You do not have those cards');
    _require(
      cards.length <= state.defender.handSize,
      'Cannot attack with more cards than the defender holds',
    );

    for (final c in cards) {
      player.removeCard(c);
      state.table.addAttack(c);
    }
    state.passedPlayers.clear();
    state.phase = GamePhase.defending;
  }

  /// Defender covers one uncovered attack card with a higher or trump card.
  void defend(String playerId, Card attackCard, Card defenseCard) {
    _require(state.phase == GamePhase.defending, 'Not in defending phase');
    _require(playerId == state.defender.id, 'Not your turn to defend');
    final player = _requirePlayer(playerId);
    _require(player.hasCard(defenseCard), 'You do not have that card');
    _require(
      defenseCard.beats(attackCard, state.trump),
      'Card does not beat the attack card',
    );
    _require(
      state.table.defend(attackCard, defenseCard),
      'Attack card not found on table or already covered',
    );
    player.removeCard(defenseCard);

    final coveredCount = state.table.entries.where((e) => e.defense != null).length;
    if (coveredCount >= _maxTableCards || (state.discard.isEmpty && coveredCount >= 5)) {
      _endTurnSuccess();
      return;
    }

    if (state.table.isAllDefended) {
      state.passedPlayers.clear();
      state.phase = GamePhase.adding;
      _checkAutoEndTurn();
    }
  }

  /// Defender transfers uncovered attack cards (+ new same-rank cards) to the
  /// next player. Already-covered pairs stay on the table as settled.
  /// Valid at any point as long as all *uncovered* attack cards share one rank.
  void transfer(String playerId, List<Card> cards) {
    _require(state.phase == GamePhase.defending, 'Not in defending phase');
    _require(playerId == state.defender.id, 'Only the defender can transfer');
    _require(cards.isNotEmpty, 'Must play at least one card');
    _require(!state.isFirstTurn, 'Transfer is not allowed on the first turn');

    final uncoveredRanks = state.table.entries
        .where((e) => e.isUndefended)
        .map((e) => e.attack.rank)
        .toSet();
    _require(uncoveredRanks.isNotEmpty, 'No uncovered cards to transfer');
    _require(
      uncoveredRanks.length == 1,
      'All uncovered attack cards must share a rank to transfer',
    );
    _require(
      cards.every((c) => c.rank == uncoveredRanks.first),
      'Transfer cards must match the uncovered attack rank',
    );

    final player = _requirePlayer(playerId);
    _require(player.hasAllCards(cards), 'You do not have those cards');

    final totalAfter = state.table.size + cards.length;
    _require(totalAfter <= _maxTableCards, 'Too many cards on table');

    // Next defender only needs to cover currently uncovered + new cards.
    final uncoveredAfter =
        state.table.entries.where((e) => e.isUndefended).length + cards.length;
    final nextDefIdx = state.nextActiveIndex(state.defenderIndex);
    _require(
      uncoveredAfter <= state.players[nextDefIdx].handSize,
      'Next player does not have enough cards to defend',
    );

    for (final c in cards) {
      player.removeCard(c);
      state.table.addAttack(c);
    }
    // Former defender becomes new attacker; next player becomes defender.
    state.attackerIndex = state.defenderIndex;
    state.defenderIndex = nextDefIdx;
    state.passedPlayers.clear();
  }

  /// Attacker or next-after-defender adds cards whose rank is already on the table.
  void addAttack(String playerId, List<Card> cards) {
    _require(
      state.phase == GamePhase.defending || state.phase == GamePhase.adding,
      'Cannot add cards in this phase',
    );
    _require(
      _addingPlayerIds().contains(playerId),
      'Only the attacker and the player after the defender may add cards',
    );
    _require(cards.isNotEmpty, 'Must add at least one card');

    final player = _requirePlayer(playerId);
    _require(player.hasAllCards(cards), 'You do not have those cards');
    _require(
      cards.every((c) => state.table.presentRanks.contains(c.rank)),
      'Cards must share a rank already on the table',
    );

    final undefendedAfter =
        state.table.entries.where((e) => e.isUndefended).length + cards.length;
    _require(
      undefendedAfter <= state.defender.handSize,
      'Defender does not have enough cards to cover',
    );
    _require(
      state.table.size + cards.length <= _maxTableCards,
      'Too many cards on table (max $_maxTableCards)',
    );

    for (final c in cards) {
      player.removeCard(c);
      state.table.addAttack(c);
    }
    state.passedPlayers.remove(playerId);

    if (state.table.hasUndefended) {
      state.phase = GamePhase.defending;
    }
  }

  /// Attacker or next-after-defender passes their right to add more cards.
  /// When both eligible players pass, the turn ends successfully.
  void pass(String playerId) {
    _require(state.phase == GamePhase.adding, 'Can only pass during adding phase');
    _require(
      _addingPlayerIds().contains(playerId),
      'Only the attacker and the player after the defender may pass',
    );

    state.passedPlayers.add(playerId);

    final mustPass = _addingPlayerIds()
        .where((id) {
          final p = state.players.firstWhere((p) => p.id == id);
          return !p.hasLeft && p.hasCards;
        })
        .toSet();

    if (state.passedPlayers.containsAll(mustPass)) {
      _endTurnSuccess();
    }
  }

  /// Defender takes all table cards into their hand. Turn passes to next player.
  void take(String playerId) {
    _require(state.phase == GamePhase.defending, 'Can only take during defending phase');
    _require(playerId == state.defender.id, 'Only the defender can take');

    state.isFirstTurn = false;
    state.defender.addCards(state.table.takeAll());

    final nextAtkIdx = state.nextActiveIndex(state.defenderIndex);
    _replenishAndAdvance(
      replenishFrom: state.nextActiveIndex(state.defenderIndex),
      nextAttackerIdx: nextAtkIdx,
    );
  }

  // ── Internal turn lifecycle ───────────────────────────────────────────────────

  /// Ends the turn immediately if both eligible players (attacker + next-after-defender)
  /// have either passed or have no cards left to add.
  void _checkAutoEndTurn() {
    if (state.phase != GamePhase.adding) return;
    final mustPass = _addingPlayerIds()
        .where((id) {
          final p = state.players.firstWhere((p) => p.id == id);
          return !p.hasLeft && p.hasCards;
        })
        .toSet();
    if (mustPass.isEmpty || state.passedPlayers.containsAll(mustPass)) {
      _endTurnSuccess();
    }
  }

  void _endTurnSuccess() {
    state.isFirstTurn = false;
    state.discard.addAll(state.table.takeAll());
    final defIdx = state.defenderIndex;
    _replenishAndAdvance(
      replenishFrom: state.nextActiveIndex(defIdx),
      nextAttackerIdx: defIdx,
    );
  }

  void _replenishAndAdvance({
    required int replenishFrom,
    required int nextAttackerIdx,
  }) {
    _replenish(replenishFrom);
    _eliminateEmptyPlayers();
    _advanceGame(nextAttackerIdx);
  }

  /// Clockwise from [startIndex], each active player draws up to [_replenishTo] cards.
  void _replenish(int startIndex) {
    if (state.deck.isEmpty) return;
    var idx = startIndex;
    final seen = <int>{};
    while (state.deck.isNotEmpty && seen.length < state.players.length) {
      if (seen.contains(idx)) break;
      seen.add(idx);
      final p = state.players[idx];
      if (!p.hasLeft) {
        final need = _replenishTo - p.handSize;
        if (need > 0) p.addCards(state.deck.drawMany(need));
      }
      idx = (idx + 1) % state.players.length;
    }
  }

  void _eliminateEmptyPlayers() {
    if (state.deck.isNotEmpty) return;
    for (final p in state.players) {
      if (!p.hasLeft && !p.hasCards) p.markLeft();
    }
  }

  void _advanceGame(int preferredAttackerIdx) {
    final active = state.players.where((p) => !p.hasLeft).toList();

    if (active.length <= 1) {
      state.loserId = active.isEmpty ? null : active.first.id;
      state.phase = GamePhase.finished;
      return;
    }

    var atkIdx = preferredAttackerIdx;
    while (state.players[atkIdx].hasLeft) {
      atkIdx = (atkIdx + 1) % state.players.length;
    }
    state.attackerIndex = atkIdx;
    state.defenderIndex = state.nextActiveIndex(atkIdx);
    state.passedPlayers.clear();
    state.phase = GamePhase.attacking;
  }
}
