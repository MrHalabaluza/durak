import 'package:durak_logic/durak_logic.dart';
import '../connection.dart';
import '../protocol.dart';
import '../room_manager.dart';

void handleLobby(Connection conn, ClientMessage msg) {
  switch (msg) {
    case CreateRoomMsg():
      _create(conn);
    case JoinRoomMsg(:final roomId):
      _join(conn, roomId);
    case LeaveRoomMsg():
      _leave(conn);
    case StartGameMsg(:final deckConfig):
      _start(conn, deckConfig);
    default:
  }
}

void _create(Connection conn) {
  if (conn.room != null) {
    conn.send(errorMsg('Already in a room'));
    return;
  }
  final room = RoomManager.instance.create();
  room.addPlayer(conn);
  conn.send(roomJoinedMsg(room.id, conn.playerId));
  conn.send(roomStateMsg(room.id, room.playerIds, false));
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
  if (!room.addPlayer(conn)) {
    conn.send(errorMsg('Cannot join: room is full or game already started'));
    return;
  }
  conn.send(roomJoinedMsg(room.id, conn.playerId));
  room.broadcast(roomStateMsg(room.id, room.playerIds, room.isStarted));
}

void _leave(Connection conn) {
  final room = conn.room;
  if (room == null) return;
  room.removePlayer(conn);
  if (room.isEmpty) {
    RoomManager.instance.removeIfEmpty(room.id);
  } else {
    room.broadcast(roomStateMsg(room.id, room.playerIds, room.isStarted));
  }
}

void _start(Connection conn, DeckConfig? deckConfig) {
  final room = conn.room;
  if (room == null) {
    conn.send(errorMsg('Not in a room'));
    return;
  }
  if (!room.startGame(deckConfig)) {
    conn.send(errorMsg('Cannot start: need 2–6 players'));
  }
}
