import 'card.dart';
import 'deck.dart';
import 'player.dart';
import 'table.dart';

enum GamePhase {
  /// Attacker must play initial cards.
  attacking,

  /// Defender responds; table has uncovered cards.
  defending,

  /// All cards covered; non-defenders may add more or pass.
  adding,

  /// Defender declared take; neighbors may pile on before cards are taken.
  taking,

  /// Game over.
  finished,
}

class GameState {
  final List<Player> players;
  final Suit trump;
  final Deck deck;
  final List<Card> discard;
  final TableState table;
  int attackerIndex;
  int defenderIndex;
  GamePhase phase;
  final Set<String> passedPlayers;

  /// Index of the player who currently holds the "add/pass token".
  /// Starts as the attacker; switches to next-after-defender on pass.
  int currentAdderIndex;

  /// True until the first successful discard (bito) or first take.
  bool isFirstTurn;

  /// Null = draw (no loser); set when [phase] == [GamePhase.finished].
  String? loserId;

  GameState({
    required this.players,
    required this.trump,
    required this.deck,
    required this.attackerIndex,
    required this.defenderIndex,
    this.phase = GamePhase.attacking,
  })  : discard = [],
        table = TableState(),
        passedPlayers = {},
        currentAdderIndex = attackerIndex,
        isFirstTurn = true;

  Player get attacker => players[attackerIndex];
  Player get defender => players[defenderIndex];

  List<Player> get activePlayers => players.where((p) => !p.hasLeft).toList();

  /// Returns the index of the next active (not-left) player after [from].
  int nextActiveIndex(int from) {
    var idx = (from + 1) % players.length;
    var steps = 0;
    while (players[idx].hasLeft && steps < players.length) {
      idx = (idx + 1) % players.length;
      steps++;
    }
    return idx;
  }
}
