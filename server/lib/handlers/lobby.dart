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
    case RejoinRoomMsg(:final roomId):
      _rejoin(conn, roomId);
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
  conn.send(roomStateMsg(room.id, room.playerEntries, false));
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
  room.broadcast(roomStateMsg(room.id, room.playerEntries, room.isStarted));
}

void _leave(Connection conn) {
  final room = conn.room;
  if (room == null) return;
  room.removePlayer(conn);
  if (room.isEmpty) {
    RoomManager.instance.removeIfEmpty(room.id);
  } else {
    room.broadcast(
        roomStateMsg(room.id, room.playerEntries, room.isStarted));
  }
}

void _rejoin(Connection conn, String roomId) {
  if (conn.room != null) {
    conn.send(errorMsg('Already in a room'));
    return;
  }
  final room = RoomManager.instance.find(roomId);
  if (room == null) {
    conn.send(errorMsg('room_not_found'));
    return;
  }
  if (!room.rejoinPlayer(conn)) {
    conn.send(errorMsg('rejoin_failed'));
    return;
  }
  if (room.isStarted) {
    room.sendGameStateTo(conn);
  } else {
    // Игра уже закончилась — возвращаем игрока в лобби той же комнаты
    conn.send(roomJoinedMsg(room.id, conn.playerId!));
    room.broadcast(roomStateMsg(room.id, room.playerEntries, false));
  }
}

void _start(Connection conn, DeckConfig? deckConfig) {
  final room = conn.room;
  if (room == null) {
    conn.send(errorMsg('Not in a room'));
    return;
  }
  if (!room.startGame(deckConfig)) {
    if (room.isStarted) {
      conn.send(errorMsg('Game already started'));
    } else {
      conn.send(errorMsg('Cannot start: need at least 2 players'));
    }
  }
}
