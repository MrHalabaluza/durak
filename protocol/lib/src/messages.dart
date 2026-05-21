import 'dart:convert';
import 'package:durak_logic/durak_logic.dart';
import 'codec.dart';

sealed class ClientMessage {
  const ClientMessage();

  static ClientMessage parse(String raw) {
    final map = jsonDecode(raw) as Map<String, dynamic>;
    return switch (map['type'] as String) {
      'create_room' => CreateRoomMsg(map['nickname'] as String? ?? ''),
      'join_room' =>
        JoinRoomMsg(map['roomId'] as String, map['nickname'] as String? ?? ''),
      'leave_room' => const LeaveRoomMsg(),
      'start_game' => StartGameMsg(
          map['deckConfig'] != null
              ? deckConfigFromJson(map['deckConfig'] as List<dynamic>)
              : null,
        ),
      'attack' => AttackMsg(cardsFromJson(map['cards'] as List)),
      'defend' => DefendMsg(
          cardFromJson(map['attackCard'] as Map<String, dynamic>),
          cardFromJson(map['defenseCard'] as Map<String, dynamic>),
        ),
      'transfer' => TransferMsg(cardsFromJson(map['cards'] as List)),
      'transit' =>
        TransitMsg(cardFromJson(map['card'] as Map<String, dynamic>)),
      'add_attack' => AddAttackMsg(cardsFromJson(map['cards'] as List)),
      'pass' => const PassMsg(),
      'take' => const TakeMsg(),
      'add_bot' => const AddBotMsg(),
      'remove_bot' => RemoveBotMsg(map['botId'] as String),
      'auth' => AuthMsg(map['token'] as String),
      'save_deck' => SaveDeckMsg(
          map['deckConfig'] != null
              ? deckConfigFromJson(map['deckConfig'] as List<dynamic>)
              : DeckConfig(),
        ),
      final t => throw FormatException('Unknown message type: $t'),
    };
  }

  Map<String, dynamic> toJson();
}

class AuthMsg extends ClientMessage {
  final String token;
  const AuthMsg(this.token);
  @override
  Map<String, dynamic> toJson() => {'type': 'auth', 'token': token};
}

class CreateRoomMsg extends ClientMessage {
  final String nickname;
  const CreateRoomMsg(this.nickname);
  @override
  Map<String, dynamic> toJson() =>
      {'type': 'create_room', 'nickname': nickname};
}

class JoinRoomMsg extends ClientMessage {
  final String roomId;
  final String nickname;
  const JoinRoomMsg(this.roomId, this.nickname);
  @override
  Map<String, dynamic> toJson() =>
      {'type': 'join_room', 'roomId': roomId, 'nickname': nickname};
}

class LeaveRoomMsg extends ClientMessage {
  const LeaveRoomMsg();
  @override
  Map<String, dynamic> toJson() => {'type': 'leave_room'};
}

class StartGameMsg extends ClientMessage {
  final DeckConfig? deckConfig;
  const StartGameMsg([this.deckConfig]);
  @override
  Map<String, dynamic> toJson() => {
        'type': 'start_game',
        if (deckConfig != null) 'deckConfig': deckConfigToJson(deckConfig!),
      };
}

class AttackMsg extends ClientMessage {
  final List<Card> cards;
  const AttackMsg(this.cards);
  @override
  Map<String, dynamic> toJson() =>
      {'type': 'attack', 'cards': cards.map(cardToJson).toList()};
}

class DefendMsg extends ClientMessage {
  final Card attackCard;
  final Card defenseCard;
  const DefendMsg(this.attackCard, this.defenseCard);
  @override
  Map<String, dynamic> toJson() => {
        'type': 'defend',
        'attackCard': cardToJson(attackCard),
        'defenseCard': cardToJson(defenseCard),
      };
}

class TransferMsg extends ClientMessage {
  final List<Card> cards;
  const TransferMsg(this.cards);
  @override
  Map<String, dynamic> toJson() =>
      {'type': 'transfer', 'cards': cards.map(cardToJson).toList()};
}

class TransitMsg extends ClientMessage {
  final Card card;
  const TransitMsg(this.card);
  @override
  Map<String, dynamic> toJson() =>
      {'type': 'transit', 'card': cardToJson(card)};
}

class AddAttackMsg extends ClientMessage {
  final List<Card> cards;
  const AddAttackMsg(this.cards);
  @override
  Map<String, dynamic> toJson() =>
      {'type': 'add_attack', 'cards': cards.map(cardToJson).toList()};
}

class PassMsg extends ClientMessage {
  const PassMsg();
  @override
  Map<String, dynamic> toJson() => {'type': 'pass'};
}

class TakeMsg extends ClientMessage {
  const TakeMsg();
  @override
  Map<String, dynamic> toJson() => {'type': 'take'};
}

class AddBotMsg extends ClientMessage {
  const AddBotMsg();
  @override
  Map<String, dynamic> toJson() => {'type': 'add_bot'};
}

class RemoveBotMsg extends ClientMessage {
  final String botId;
  const RemoveBotMsg(this.botId);
  @override
  Map<String, dynamic> toJson() =>
      {'type': 'remove_bot', 'botId': botId};
}

class SaveDeckMsg extends ClientMessage {
  final DeckConfig deckConfig;
  const SaveDeckMsg(this.deckConfig);
  @override
  Map<String, dynamic> toJson() =>
      {'type': 'save_deck', 'deckConfig': deckConfigToJson(deckConfig)};
}
