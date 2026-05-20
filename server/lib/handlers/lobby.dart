import 'package:durak_logic/durak_logic.dart';
import '../connection.dart';
import '../protocol.dart';
import '../room_manager.dart';
import '../db/deck_dao.dart';

void handleLobby(Connection conn, ClientMessage msg, DeckDao deckDao) {
  switch (msg) {
    case CreateRoomMsg():
      _create(conn);
    case JoinRoomMsg(:final roomId):
      _join(conn, roomId);
    case LeaveRoomMsg():
      _leave(conn);
    case StartGameMsg():
      _start(conn);
    case SaveDeckMsg(:final deckConfig):
      _saveDeck(conn, deckConfig, deckDao);
    case AddBotMsg():
      _addBot(conn);
    case RemoveBotMsg(:final botId):
      _removeBot(conn, botId);
    default:
  }
}

void _create(Connection conn) {
  if (conn.room != null) {
    conn.send(errorMsg('Already in a room'));
    return;
  }
  conn.nickname = conn.username!;
  final room = RoomManager.instance.create();
  room.addPlayer(conn);
  conn.send(roomJoinedMsg(room.id, conn.playerId!));
  conn.send(roomStateMsg(room.id, room.playerEntries, false,
      ownerId: room.ownerId));
}

void _join(Connection conn, String roomId) {
  if (conn.room != null) {
    conn.send(errorMsg('Already in a room'));
    return;
  }
  final room = RoomManager.instance.find(roomId);
  if (room == null) {
    conn.send(errorMsg('Room not found'));
    return;
  }
  conn.nickname = conn.username!;
  if (!room.addPlayer(conn)) {
    conn.send(errorMsg('Cannot join: room is full or game already started'));
    return;
  }
  conn.send(roomJoinedMsg(room.id, conn.playerId!));
  room.broadcast(
      roomStateMsg(room.id, room.playerEntries, room.isStarted,
          ownerId: room.ownerId));
}

void _leave(Connection conn) {
  final room = conn.room;
  if (room == null) return;
  room.removePlayer(conn);
  if (room.isEmpty) {
    RoomManager.instance.removeIfEmpty(room.id);
  } else {
    room.broadcast(
        roomStateMsg(room.id, room.playerEntries, room.isStarted,
            ownerId: room.ownerId));
  }
}

void _start(Connection conn) {
  final room = conn.room;
  if (room == null) {
    conn.send(errorMsg('Not in a room'));
    return;
  }
  if (conn.playerId != room.ownerId) {
    conn.send(errorMsg('Only the room owner can start the game'));
    return;
  }
  if (!room.startGame(conn.savedDeckConfig)) {
    if (room.isStarted) {
      conn.send(errorMsg('Game already started'));
    } else {
      conn.send(errorMsg('Cannot start: need at least 2 players'));
    }
  }
}

void _saveDeck(Connection conn, DeckConfig deckConfig, DeckDao deckDao) {
  if (conn.room?.isStarted ?? false) {
    conn.send(errorMsg('Cannot change deck while game is in progress'));
    return;
  }
  final userId = int.tryParse(conn.playerId ?? '');
  if (userId == null) return;
  deckDao.save(userId, deckConfig);
  conn.savedDeckConfig = deckConfig;
}

void _addBot(Connection conn) {
  final room = conn.room;
  if (room == null) {
    conn.send(errorMsg('Not in a room'));
    return;
  }
  if (conn.playerId != room.ownerId) {
    conn.send(errorMsg('Only the room owner can add bots'));
    return;
  }
  if (!room.addBot()) {
    conn.send(errorMsg('Cannot add bot: room is full or game already started'));
    return;
  }
  room.broadcast(
      roomStateMsg(room.id, room.playerEntries, false, ownerId: room.ownerId));
}

void _removeBot(Connection conn, String botId) {
  final room = conn.room;
  if (room == null) {
    conn.send(errorMsg('Not in a room'));
    return;
  }
  if (conn.playerId != room.ownerId) {
    conn.send(errorMsg('Only the room owner can remove bots'));
    return;
  }
  if (!room.removeBot(botId)) {
    conn.send(errorMsg('Bot not found'));
    return;
  }
  room.broadcast(
      roomStateMsg(room.id, room.playerEntries, false, ownerId: room.ownerId));
}
