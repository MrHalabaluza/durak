import 'package:durak_logic/durak_logic.dart';
import 'package:durak_protocol/durak_protocol.dart';

export 'package:durak_protocol/durak_protocol.dart'
    show
        ClientMessage,
        AuthMsg,
        CreateRoomMsg,
        JoinRoomMsg,
        LeaveRoomMsg,
        StartGameMsg,
        AttackMsg,
        DefendMsg,
        TransferMsg,
        TransitMsg,
        AddAttackMsg,
        PassMsg,
        TakeMsg,
        AddBotMsg,
        RemoveBotMsg,
        SaveDeckMsg,
        GameStateView,
        PlayerView,
        TableEntryView,
        cardToJson,
        cardFromJson,
        deckConfigToJson,
        deckConfigFromJson;

// ── Server-only outgoing message builders ───────────────────────────────────

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
      'deckConfig': deckConfigToJson(deckConfig),
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
) =>
    GameStateView.fromGameState(state, playerId, addingPlayerIds, nicknames)
        .toJson();
