import 'dart:io';
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
import 'package:durak_server/auth/ws_auth.dart';
import 'package:durak_server/http/router.dart';
import 'package:durak_server/http/handlers_auth.dart';
import 'package:durak_server/http/handlers_me.dart';
import 'package:durak_server/http/handlers_users.dart';
import 'package:durak_server/http/handlers_stats.dart';
import 'package:durak_server/http/handlers_avatar.dart';

void main() async {
  final port = int.parse(Platform.environment['PORT'] ?? '8080');

  final dbPath = Platform.environment['DURAK_DB_PATH'] ?? '/data/durak.db';
  final db = AppDatabase.open(dbPath);
  final userDao = UserDao(db.db);
  final sessionDao = SessionDao(db.db);
  final statsDao = StatsDao(db.db);
  final auth = AuthService(userDao, sessionDao);
  RoomManager.init(statsDao);
  final avatarsDir =
      Platform.environment['DURAK_AVATARS_DIR'] ?? '/data/avatars';

  var total = 0;

  final router = Router()
    ..add('POST', '/api/register', (r, _) => handleRegister(r, auth))
    ..add('POST', '/api/login', (r, _) => handleLogin(r, auth))
    ..add('POST', '/api/logout', (r, _) => handleLogout(r, auth))
    ..add('GET', '/api/me', (r, _) => handleGetMe(r, auth, statsDao))
    ..add('GET', '/api/users/:id', (r, p) => handleGetUser(r, p, userDao, statsDao))
    ..add('GET', '/api/leaderboard', (r, _) => handleLeaderboard(r, statsDao))
    ..add('GET', '/api/server-stats', (r, _) => handleServerStats(r, statsDao, total))
    ..add('POST', '/api/me/avatar', (r, _) => handleUploadAvatar(r, auth, userDao, avatarsDir))
    ..add('GET', '/avatars/:filename', (r, p) => handleGetAvatar(r, p, avatarsDir));

  final server = await HttpServer.bind(InternetAddress.anyIPv4, port);
  print('DTFool server listening on port $port');

  await for (final request in server) {
    if (WebSocketTransformer.isUpgradeRequest(request)) {
      WebSocketTransformer.upgrade(request).then((ws) {
        print('[+] new connection  (active: ${++total})');

        final innerDispatch = (Connection conn, ClientMessage msg) {
          if (msg is CreateRoomMsg ||
              msg is JoinRoomMsg ||
              msg is LeaveRoomMsg ||
              msg is StartGameMsg ||
              msg is AddBotMsg ||
              msg is RemoveBotMsg) {
            handleLobby(conn, msg);
          } else if (msg is! AuthMsg) {
            handleGame(conn, msg);
          }
        };

        Connection(
          socket: ws,
          onMessage: authedDispatch(auth, innerDispatch),
          onClose: (conn) {
            print('[-] ${conn.playerId ?? '?'}  (active: ${--total})');
            final room = conn.room;
            if (room != null) {
              room.removePlayer(conn);
              if (room.isEmpty) {
                RoomManager.instance.removeIfEmpty(room.id);
              } else if (conn.playerId != null) {
                room.broadcast(
                    {'type': 'player_left', 'playerId': conn.playerId});
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
