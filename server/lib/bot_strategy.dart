import 'package:durak_logic/durak_logic.dart';

// ── Bot actions ──────────────────────────────────────────────────────────────

sealed class BotAction {
  const BotAction();
}

class BotAttack extends BotAction {
  final List<Card> cards;
  const BotAttack(this.cards);
}

class BotDefend extends BotAction {
  final Card attackCard;
  final Card defenseCard;
  const BotDefend(this.attackCard, this.defenseCard);
}

class BotTransfer extends BotAction {
  final List<Card> cards;
  const BotTransfer(this.cards);
}

class BotTransit extends BotAction {
  final Card card;
  const BotTransit(this.card);
}

class BotAddAttack extends BotAction {
  final List<Card> cards;
  const BotAddAttack(this.cards);
}

class BotPass extends BotAction {
  const BotPass();
}

class BotTake extends BotAction {
  const BotTake();
}

// ── Strategy interface ───────────────────────────────────────────────────────

abstract class BotStrategy {
  BotAction chooseAction(
    GameState state,
    String botId,
    Set<String> addingPlayerIds,
  );
}

// ── Simple bot implementation ────────────────────────────────────────────────

class SimpleBot implements BotStrategy {
  @override
  BotAction chooseAction(
    GameState state,
    String botId,
    Set<String> addingPlayerIds,
  ) {
    return switch (state.phase) {
      GamePhase.attacking => _attack(state, botId),
      GamePhase.defending => _defend(state, botId),
      GamePhase.adding || GamePhase.taking => _add(state, botId),
      GamePhase.finished => const BotPass(),
    };
  }

  BotAction _attack(GameState state, String botId) {
    final trump = state.trump;
    final hand = state.players.firstWhere((p) => p.id == botId).hand;

    final nonTrump = hand.where((c) => c.suit != trump).toList()
      ..sort((a, b) => a.rank.index.compareTo(b.rank.index));
    if (nonTrump.isNotEmpty) return BotAttack([nonTrump.first]);

    final trumpCards = hand.where((c) => c.suit == trump).toList()
      ..sort((a, b) => a.rank.index.compareTo(b.rank.index));
    if (trumpCards.isNotEmpty) return BotAttack([trumpCards.first]);

    return const BotPass();
  }

  BotAction _defend(GameState state, String botId) {
    final trump = state.trump;
    final player = state.players.firstWhere((p) => p.id == botId);

    if (!state.isFirstTurn) {
      final uncoveredEntries = state.table.entries.where((e) => e.isUndefended).toList();
      final uncoveredRanks = uncoveredEntries.map((e) => e.attack.rank).toSet();

      if (uncoveredRanks.length == 1) {
        final rank = uncoveredRanks.first;
        final nextDefIdx = state.nextActiveIndex(state.defenderIndex);
        final nextHandSize = state.players[nextDefIdx].handSize;
        final uncoveredCount = uncoveredEntries.length;

        // Try transit first
        final transitCard = player.hand
            .where((c) =>
                c.suit == trump &&
                c.rank == rank &&
                !state.transitUsedThisTurn.contains(c.id))
            .firstOrNull;
        if (transitCard != null && uncoveredCount <= nextHandSize) {
          return BotTransit(transitCard);
        }

        // Try transfer
        final transferCards =
            player.hand.where((c) => c.rank == rank).toList();
        if (transferCards.isNotEmpty) {
          final effectiveMax = state.discard.isEmpty ? 5 : 9;
          final totalAfter = state.table.size + transferCards.length;
          final uncoveredAfter = uncoveredCount + transferCards.length;
          if (totalAfter <= effectiveMax && uncoveredAfter <= nextHandSize) {
            return BotTransfer(transferCards);
          }
        }
      }
    }

    // Try to defend one uncovered card
    final uncovered = state.table.entries.where((e) => e.isUndefended).toList();
    if (uncovered.isNotEmpty) {
      final attackCard = uncovered.first.attack;

      final nonTrumpDefenders = player.hand
          .where((c) => c.suit != trump && c.beats(attackCard, trump))
          .toList()
        ..sort((a, b) => a.rank.index.compareTo(b.rank.index));
      if (nonTrumpDefenders.isNotEmpty) {
        return BotDefend(attackCard, nonTrumpDefenders.first);
      }

      final trumpDefenders = player.hand
          .where((c) => c.suit == trump && c.beats(attackCard, trump))
          .toList()
        ..sort((a, b) => a.rank.index.compareTo(b.rank.index));
      if (trumpDefenders.isNotEmpty) {
        return BotDefend(attackCard, trumpDefenders.first);
      }
    }

    return const BotTake();
  }

  BotAction _add(GameState state, String botId) {
    final trump = state.trump;
    final player = state.players.firstWhere((p) => p.id == botId);
    final presentRanks = state.table.presentRanks;
    final effectiveMax = state.discard.isEmpty ? 5 : 9;

    // Candidates: non-trump cards whose rank is on the table
    var candidates = player.hand
        .where((c) => c.suit != trump && presentRanks.contains(c.rank))
        .toList()
      ..sort((a, b) => a.rank.index.compareTo(b.rank.index));

    if (candidates.isEmpty) return const BotPass();

    final uncoveredNow =
        state.table.entries.where((e) => e.isUndefended).length;
    final defenderHandSize = state.defender.handSize;
    final tableSize = state.table.size;

    // Greedily add as many cards as limits allow
    final toAdd = <Card>[];
    for (final card in candidates) {
      final newUncovered = uncoveredNow + toAdd.length + 1;
      final newTableSize = tableSize + toAdd.length + 1;
      if (newTableSize > effectiveMax) break;
      if (newUncovered > defenderHandSize) break;
      // In adding phase (not taking), also check adder's hand doesn't go below uncovered count
      if (state.phase == GamePhase.adding &&
          newUncovered > player.handSize - toAdd.length) break;
      toAdd.add(card);
    }

    if (toAdd.isEmpty) return const BotPass();
    return BotAddAttack(toAdd);
  }
}
