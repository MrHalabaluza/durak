import 'dart:convert';
import 'package:durak_logic/durak_logic.dart';

// ── Incoming message types ──────────────────────────────────────────────────

sealed class ClientMessage {
  const ClientMessage();

  static ClientMessage parse(String raw) {
    final map = jsonDecode(raw) as Map<String, dynamic>;
    return switch (map['type'] as String) {
      'create_room' => CreateRoomMsg(map['nickname'] as String? ?? ''),
      'join_room' => JoinRoomMsg(
          map['roomId'] as String, map['nickname'] as String? ?? ''),
      'leave_room' => const LeaveRoomMsg(),
      'start_game' => StartGameMsg(
          map['deckConfig'] != null
              ? _parseDeckConfig(map['deckConfig'] as List<dynamic>)
              : null,
        ),
      'attack' => AttackMsg(_parseCards(map['cards'] as List)),
      'defend' => DefendMsg(
          _parseCard(map['attackCard'] as Map<String, dynamic>),
          _parseCard(map['defenseCard'] as Map<String, dynamic>),
        ),
      'transfer' => TransferMsg(_parseCards(map['cards'] as List)),
      'transit' => TransitMsg(_parseCard(map['card'] as Map<String, dynamic>)),
      'add_attack' => AddAttackMsg(_parseCards(map['cards'] as List)),
      'pass' => const PassMsg(),
      'take' => const TakeMsg(),
      'add_bot' => const AddBotMsg(),
      'remove_bot' => RemoveBotMsg(map['botId'] as String),
      'auth' => AuthMsg(map['token'] as String),
      'save_deck' => SaveDeckMsg(
          map['deckConfig'] != null
              ? _parseDeckConfig(map['deckConfig'] as List<dynamic>)
              : DeckConfig(),
        ),
      final t => throw FormatException('Unknown message type: $t'),
    };
  }
}

class AuthMsg extends ClientMessage {
  final String token;
  const AuthMsg(this.token);
}

class CreateRoomMsg extends ClientMessage {
  final String nickname;
  const CreateRoomMsg(this.nickname);
}

class JoinRoomMsg extends ClientMessage {
  final String roomId;
  final String nickname;
  const JoinRoomMsg(this.roomId, this.nickname);
}

class LeaveRoomMsg extends ClientMessage {
  const LeaveRoomMsg();
}

class StartGameMsg extends ClientMessage {
  final DeckConfig? deckConfig;
  StartGameMsg([this.deckConfig]);
}

class AttackMsg extends ClientMessage {
  final List<Card> cards;
  AttackMsg(this.cards);
}

class DefendMsg extends ClientMessage {
  final Card attackCard;
  final Card defenseCard;
  DefendMsg(this.attackCard, this.defenseCard);
}

class TransferMsg extends ClientMessage {
  final List<Card> cards;
  TransferMsg(this.cards);
}

class TransitMsg extends ClientMessage {
  final Card card;
  TransitMsg(this.card);
}

class AddAttackMsg extends ClientMessage {
  final List<Card> cards;
  AddAttackMsg(this.cards);
}

class PassMsg extends ClientMessage {
  const PassMsg();
}

class TakeMsg extends ClientMessage {
  const TakeMsg();
}

class AddBotMsg extends ClientMessage {
  const AddBotMsg();
}

class RemoveBotMsg extends ClientMessage {
  final String botId;
  const RemoveBotMsg(this.botId);
}

class SaveDeckMsg extends ClientMessage {
  final DeckConfig deckConfig;
  const SaveDeckMsg(this.deckConfig);
}

// ── Outgoing message builders ───────────────────────────────────────────────

Map<String, dynamic> errorMsg(String message) =>
    {'type': 'error', 'message': message};

Map<String, dynamic> authOkMsg(
  int userId,
  String username,
  DeckConfig deckConfig,
) =>
    {
      'type': 'auth_ok',
      'userId': userId.toString(),
      'username': username,
      'deckConfig': deckConfig.counts.entries
          .where((e) => e.value > 0)
          .map((e) => {
                'suit': e.key.suit.name,
                'rank': e.key.rank.name,
                'count': e.value,
              })
          .toList(),
    };

Map<String, dynamic> roomJoinedMsg(String roomId, String playerId) => {
      'type': 'room_joined',
      'roomId': roomId,
      'playerId': playerId,
    };

Map<String, dynamic> roomStateMsg(
  String roomId,
  List<({String id, String nickname, bool isBot})> players,
  bool started, {
  String? ownerId,
}) =>
    {
      'type': 'room_state',
      'roomId': roomId,
      'ownerId': ownerId,
      'players': players
          .map((p) => {'id': p.id, 'nickname': p.nickname, 'isBot': p.isBot})
          .toList(),
      'started': started,
    };

Map<String, dynamic> gameStateMsg(
  GameState state,
  String playerId,
  Set<String> addingPlayerIds,
  Map<String, String> nicknames,
) {
  final player = state.players.firstWhere(
    (p) => p.id == playerId,
    orElse: () => throw StateError('Player $playerId not in game'),
  );
  return {
    'type': 'game_state',
    'phase': state.phase.name,
    'trump': state.trump.name,
    'deckSize': state.deck.size,
    'discardSize': state.discard.length,
    'attackerIndex': state.attackerIndex,
    'defenderIndex': state.defenderIndex,
    'currentAdderIndex': state.currentAdderIndex,
    'isFirstTurn': state.isFirstTurn,
    'addingPlayerIds': addingPlayerIds.toList(),
    'hand': player.hand.map(_serializeCard).toList(),
    'players': state.players
        .map((p) => {
              'id': p.id,
              'nickname': nicknames[p.id] ?? p.id,
              'handSize': p.handSize,
              'hasLeft': p.hasLeft,
            })
        .toList(),
    'table': state.table.entries
        .map((e) => {
              'attack': _serializeCard(e.attack),
              'defense': e.defense != null ? _serializeCard(e.defense!) : null,
            })
        .toList(),
    'trumpCard': state.trumpCard != null
        ? _serializeCard(state.trumpCard!)
        : null,
    'loserId': state.loserId,
  };
}

// ── Helpers ─────────────────────────────────────────────────────────────────

Map<String, dynamic> _serializeCard(Card card) =>
    {'id': card.id, 'suit': card.suit.name, 'rank': card.rank.name};

Card _parseCard(Map<String, dynamic> map) => Card.withId(
      map['id'] as int,
      Suit.values.byName(map['suit'] as String),
      Rank.values.byName(map['rank'] as String),
    );

List<Card> _parseCards(List<dynamic> list) =>
    list.map((e) => _parseCard(e as Map<String, dynamic>)).toList();

DeckConfig _parseDeckConfig(List<dynamic> list) {
  final counts = <Card, int>{};
  for (final entry in list) {
    final map = entry as Map<String, dynamic>;
    final count = map['count'] as int;
    if (count > 0) {
      counts[Card(
        Suit.values.byName(map['suit'] as String),
        Rank.values.byName(map['rank'] as String),
      )] = count;
    }
  }
  return DeckConfig.custom(counts);
}
