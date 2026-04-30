import 'dart:io';
import 'dart:math';
import 'package:durak_server/connection.dart';
import 'package:durak_server/protocol.dart';
import 'package:durak_server/room_manager.dart';
import 'package:durak_server/handlers/lobby.dart';
import 'package:durak_server/handlers/game.dart';
import 'package:durak_server/db/database.dart';
import 'package:durak_server/db/user_dao.dart';
import 'package:durak_server/db/session_dao.dart';
import 'package:durak_server/db/stats_dao.dart';
import 'package:durak_server/auth/auth_service.dart';
import 'package:durak_server/http/router.dart';
import 'package:durak_server/http/handlers_auth.dart';
import 'package:durak_server/http/handlers_me.dart';

void main() async {
  final port = int.parse(Platform.environment['PORT'] ?? '8080');

  final dbPath =
      Platform.environment['DURAK_DB_PATH'] ?? '/data/durak.db';
  final db = AppDatabase.open(dbPath);
  final userDao = UserDao(db.db);
  final sessionDao = SessionDao(db.db);
  final statsDao = StatsDao(db.db);
  final auth = AuthService(userDao, sessionDao);

  RoomManager.instance; // ensure singleton initialized

  final router = Router()
    ..add('POST', '/api/register', (r, _) => handleRegister(r, auth))
    ..add('POST', '/api/login', (r, _) => handleLogin(r, auth))
    ..add('POST', '/api/logout', (r, _) => handleLogout(r, auth))
    ..add('GET', '/api/me', (r, _) => handleGetMe(r, auth, statsDao));

  final server = await HttpServer.bind(InternetAddress.anyIPv4, port);
  print('DTFool server listening on port $port');

  var total = 0;
  final rng = Random.secure();

  String newPlayerId() => List.generate(8, (_) => rng.nextInt(256))
      .map((b) => b.toRadixString(16).padLeft(2, '0'))
      .join();

  await for (final request in server) {
    if (WebSocketTransformer.isUpgradeRequest(request)) {
      WebSocketTransformer.upgrade(request).then((ws) {
        final playerId = newPlayerId();
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
      continue;
    }

    if (await router.dispatch(request)) continue;
    request.response
      ..statusCode = HttpStatus.notFound
      ..close();
  }
}
