import 'package:durak_logic/durak_logic.dart';
import '../connection.dart';
import '../protocol.dart';
import '../room_manager.dart';

void handleLobby(Connection conn, ClientMessage msg) {
  switch (msg) {
    case CreateRoomMsg(:final nickname):
      _create(conn, nickname);
    case JoinRoomMsg(:final roomId, :final nickname):
      _join(conn, roomId, nickname);
    case LeaveRoomMsg():
      _leave(conn);
    case StartGameMsg(:final deckConfig):
      _start(conn, deckConfig);
    default:
  }
}

void _create(Connection conn, String nickname) {
  if (conn.room != null) {
    conn.send(errorMsg('Already in a room'));
    return;
  }
  conn.nickname = _resolveNickname(nickname, conn.playerId, const []);
  final room = RoomManager.instance.create();
  room.addPlayer(conn);
  conn.send(roomJoinedMsg(room.id, conn.playerId));
  conn.send(roomStateMsg(room.id, room.playerEntries, false));
}

void _join(Connection conn, String roomId, String nickname) {
  if (conn.room != null) {
    conn.send(errorMsg('Already in a room'));
    return;
  }
  final room = RoomManager.instance.find(roomId);
  if (room == null) {
    conn.send(errorMsg('Room not found'));
    return;
  }
  conn.nickname =
      _resolveNickname(nickname, conn.playerId, room.playerEntries);
  if (!room.addPlayer(conn)) {
    conn.send(errorMsg('Cannot join: room is full or game already started'));
    return;
  }
  conn.send(roomJoinedMsg(room.id, conn.playerId));
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

/// Returns [desired] if not already taken; otherwise appends `_2`, `_3`, etc.
String _resolveNickname(
  String desired,
  String ownId,
  List<({String id, String nickname})> existing,
) {
  final base = desired.trim().isEmpty ? ownId.substring(0, 6) : desired.trim();
  final taken = existing.map((e) => e.nickname).toSet();
  if (!taken.contains(base)) return base;
  var i = 2;
  while (taken.contains('${base}_$i')) {
    i++;
  }
  return '${base}_$i';
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
