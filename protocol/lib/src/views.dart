import 'package:durak_logic/durak_logic.dart';
import 'codec.dart';

class PlayerView {
  final String id;
  final String nickname;
  final int handSize;
  final bool hasLeft;
  const PlayerView(this.id, this.nickname, this.handSize, this.hasLeft);
}

class TableEntryView {
  final Card attack;
  final Card? defense;
  const TableEntryView(this.attack, this.defense);
}

class GameStateView {
  final GamePhase phase;
  final Suit trump;
  final Card? trumpCard;
  final int deckSize;
  final int discardSize;
  final int attackerIndex;
  final int defenderIndex;
  final int currentAdderIndex;
  final bool isFirstTurn;
  final List<String> addingPlayerIds;
  final List<Card> hand;
  final List<PlayerView> players;
  final List<TableEntryView> table;
  final String? loserId;

  const GameStateView({
    required this.phase,
    required this.trump,
    this.trumpCard,
    required this.deckSize,
    required this.discardSize,
    required this.attackerIndex,
    required this.defenderIndex,
    required this.currentAdderIndex,
    required this.isFirstTurn,
    required this.addingPlayerIds,
    required this.hand,
    required this.players,
    required this.table,
    this.loserId,
  });

  factory GameStateView.fromJson(Map<String, dynamic> m) => GameStateView(
        phase: GamePhase.values.byName(m['phase'] as String),
        trump: Suit.values.byName(m['trump'] as String),
        trumpCard: m['trumpCard'] != null
            ? cardFromJson(m['trumpCard'] as Map<String, dynamic>)
            : null,
        deckSize: m['deckSize'] as int,
        discardSize: m['discardSize'] as int,
        attackerIndex: m['attackerIndex'] as int,
        defenderIndex: m['defenderIndex'] as int,
        currentAdderIndex: m['currentAdderIndex'] as int,
        isFirstTurn: m['isFirstTurn'] as bool? ?? false,
        addingPlayerIds: List<String>.from(m['addingPlayerIds'] as List),
        hand: cardsFromJson(m['hand'] as List),
        players: (m['players'] as List).map((e) {
          final p = e as Map<String, dynamic>;
          return PlayerView(
            p['id'] as String,
            p['nickname'] as String? ?? '',
            p['handSize'] as int,
            p['hasLeft'] as bool,
          );
        }).toList(),
        table: (m['table'] as List).map((e) {
          final t = e as Map<String, dynamic>;
          return TableEntryView(
            cardFromJson(t['attack'] as Map<String, dynamic>),
            t['defense'] != null
                ? cardFromJson(t['defense'] as Map<String, dynamic>)
                : null,
          );
        }).toList(),
        loserId: m['loserId'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'type': 'game_state',
        'phase': phase.name,
        'trump': trump.name,
        'deckSize': deckSize,
        'discardSize': discardSize,
        'attackerIndex': attackerIndex,
        'defenderIndex': defenderIndex,
        'currentAdderIndex': currentAdderIndex,
        'isFirstTurn': isFirstTurn,
        'addingPlayerIds': addingPlayerIds,
        'hand': hand.map(cardToJson).toList(),
        'players': players
            .map((p) => {
                  'id': p.id,
                  'nickname': p.nickname,
                  'handSize': p.handSize,
                  'hasLeft': p.hasLeft,
                })
            .toList(),
        'table': table
            .map((e) => {
                  'attack': cardToJson(e.attack),
                  'defense': e.defense != null ? cardToJson(e.defense!) : null,
                })
            .toList(),
        if (trumpCard != null) 'trumpCard': cardToJson(trumpCard!),
        'loserId': loserId,
      };

  factory GameStateView.fromGameState(
    GameState state,
    String playerId,
    Set<String> addingPlayerIds,
    Map<String, String> nicknames,
  ) {
    final player = state.players.firstWhere(
      (p) => p.id == playerId,
      orElse: () => throw StateError('Player $playerId not in game'),
    );
    return GameStateView(
      phase: state.phase,
      trump: state.trump,
      trumpCard: state.trumpCard,
      deckSize: state.deck.size,
      discardSize: state.discard.length,
      attackerIndex: state.attackerIndex,
      defenderIndex: state.defenderIndex,
      currentAdderIndex: state.currentAdderIndex,
      isFirstTurn: state.isFirstTurn,
      addingPlayerIds: addingPlayerIds.toList(),
      hand: List.of(player.hand),
      players: state.players
          .map((p) => PlayerView(
                p.id,
                nicknames[p.id] ?? p.id,
                p.handSize,
                p.hasLeft,
              ))
          .toList(),
      table: state.table.entries
          .map((e) => TableEntryView(e.attack, e.defense))
          .toList(),
      loserId: state.loserId,
    );
  }
}
