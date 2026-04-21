import 'dart:io';
import 'dart:math';
import 'package:durak_server/connection.dart';
import 'package:durak_server/protocol.dart';
import 'package:durak_server/room_manager.dart';
import 'package:durak_server/handlers/lobby.dart';
import 'package:durak_server/handlers/game.dart';

void main() async {
  final port = int.parse(Platform.environment['PORT'] ?? '8080');
  final server = await HttpServer.bind(InternetAddress.anyIPv4, port);
  print('DTFool server listening on port $port');

  var total = 0;
  final rng = Random.secure();

  String _newPlayerId() => List.generate(8, (_) => rng.nextInt(256))
      .map((b) => b.toRadixString(16).padLeft(2, '0'))
      .join();

  await for (final request in server) {
    if (!WebSocketTransformer.isUpgradeRequest(request)) {
      request.response
        ..statusCode = HttpStatus.ok
        ..headers.contentType = ContentType.text
        ..write('DTFool WebSocket server')
        ..close();
      continue;
    }

    WebSocketTransformer.upgrade(request).then((ws) {
      final playerId = _newPlayerId();
      total++;
      print('[+] $playerId  (active: $total)');

      Connection(
        playerId: playerId,
        socket: ws,
        onMessage: (conn, msg) {
          if (msg is CreateRoomMsg ||
              msg is JoinRoomMsg ||
              msg is LeaveRoomMsg ||
              msg is StartGameMsg) {
            handleLobby(conn, msg);
          } else {
            handleGame(conn, msg);
          }
        },
        onClose: (conn) {
          total--;
          print('[-] $playerId  (active: $total)');
          final room = conn.room;
          if (room != null) {
            room.removePlayer(conn);
            if (room.isEmpty) {
              RoomManager.instance.removeIfEmpty(room.id);
            } else {
              room.broadcast({'type': 'player_left', 'playerId': playerId});
            }
          }
        },
      );
    });
  }
}
