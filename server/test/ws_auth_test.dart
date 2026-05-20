import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:hashlib/hashlib.dart';
import 'package:test/test.dart';
import 'package:durak_server/connection.dart';
import 'package:durak_server/protocol.dart';
import 'package:durak_server/auth/auth_service.dart';
import 'package:durak_server/auth/ws_auth.dart';
import 'package:durak_server/db/database.dart';
import 'package:durak_server/db/user_dao.dart';
import 'package:durak_server/db/session_dao.dart';
import 'package:durak_server/handlers/lobby.dart';
import 'package:durak_server/handlers/game.dart';
import 'package:durak_server/room_manager.dart';
import 'package:durak_server/db/stats_dao.dart';
import 'package:durak_server/db/deck_dao.dart';

String _hashFast(String hex) {
  final salt = Uint8List.fromList(List.generate(16, (i) => i));
  return argon2id(
    Uint8List.fromList(hex.codeUnits),
    salt,
    security: Argon2Security.little,
  ).encoded();
}

bool _verifyFast(String hex, String encoded) =>
    argon2Verify(encoded, Uint8List.fromList(hex.codeUnits));

class _FastAuthService extends AuthService {
  final UserDao _u;
  final SessionDao _s;
  _FastAuthService(this._u, this._s) : super(_u, _s);

  @override
  ({int userId, String username, String token, String? avatarPath}) register({
    required String username,
    required String clientPasswordHash,
  }) {
    final trimmed = username.trim();
    if (_u.findByUsernameLower(trimmed.toLowerCase()) != null) {
      throw AuthException('username_taken', 'Username already in use');
    }
    final id = _u.create(
        username: trimmed, passwordHash: _hashFast(clientPasswordHash));
    final token = _s.create(id);
    return (userId: id, username: trimmed, token: token, avatarPath: null);
  }

  @override
  ({int userId, String username, String token, String? avatarPath}) login({
    required String username,
    required String clientPasswordHash,
  }) {
    final user = _u.findByUsernameLower(username.toLowerCase());
    if (user == null) throw AuthException('bad_credentials', 'Bad credentials');
    if (!_verifyFast(clientPasswordHash, user.passwordHash)) {
      throw AuthException('bad_credentials', 'Bad credentials');
    }
    final token = _s.create(user.id);
    return (
      userId: user.id,
      username: user.username,
      token: token,
      avatarPath: user.avatarPath
    );
  }
}

/// Subscribes once and queues all messages for sequential consumption.
class _WsSession {
  final WebSocket _ws;
  final _queue = <Map<String, dynamic>>[];
  final _waiters = <Completer<Map<String, dynamic>>>[];
  final _closedCompleter = Completer<void>();

  _WsSession(this._ws) {
    _ws.listen(
      (data) {
        final m = jsonDecode(data as String) as Map<String, dynamic>;
        if (_waiters.isNotEmpty) {
          _waiters.removeAt(0).complete(m);
        } else {
          _queue.add(m);
        }
      },
      onDone: () {
        for (final w in _waiters) {
          if (!w.isCompleted) w.completeError(StateError('WS closed'));
        }
        _waiters.clear();
        if (!_closedCompleter.isCompleted) _closedCompleter.complete();
      },
      onError: (e) {
        for (final w in _waiters) {
          if (!w.isCompleted) w.completeError(e);
        }
        _waiters.clear();
        if (!_closedCompleter.isCompleted) _closedCompleter.complete();
      },
    );
  }

  Future<Map<String, dynamic>> next(
      {Duration timeout = const Duration(seconds: 3)}) {
    if (_queue.isNotEmpty) return Future.value(_queue.removeAt(0));
    final c = Completer<Map<String, dynamic>>();
    _waiters.add(c);
    return c.future.timeout(timeout, onTimeout: () {
      _waiters.remove(c);
      throw TimeoutException('next() timed out', timeout);
    });
  }

  Future<void> waitClosed({Duration timeout = const Duration(seconds: 3)}) =>
      _closedCompleter.future.timeout(timeout);

  void send(Map<String, dynamic> msg) => _ws.add(jsonEncode(msg));
  Future<void> close() => _ws.close();
  int? get closeCode => _ws.closeCode;
}

void main() {
  late AppDatabase appDb;
  late HttpServer server;
  late _FastAuthService auth;
  late String validToken;
  late int port;

  setUp(() async {
    appDb = AppDatabase.open(':memory:');
    final userDao = UserDao(appDb.db);
    final sessionDao = SessionDao(appDb.db);
    final deckDao = DeckDao(appDb.db);
    auth = _FastAuthService(userDao, sessionDao);
    RoomManager.init(StatsDao(appDb.db));

    final reg = auth.register(
        username: 'TestUser', clientPasswordHash: 'deadbeef' * 8);
    validToken = reg.token;

    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    port = server.port;

    server.listen((req) {
      if (!WebSocketTransformer.isUpgradeRequest(req)) {
        req.response
          ..statusCode = 404
          ..close();
        return;
      }
      WebSocketTransformer.upgrade(req).then((ws) {
        final innerDispatch = (Connection conn, ClientMessage msg) {
          if (msg is CreateRoomMsg ||
              msg is JoinRoomMsg ||
              msg is LeaveRoomMsg ||
              msg is StartGameMsg ||
              msg is SaveDeckMsg) {
            handleLobby(conn, msg, deckDao);
          } else if (msg is! AuthMsg) {
            handleGame(conn, msg);
          }
        };
        Connection(
          socket: ws,
          onMessage: authedDispatch(auth, deckDao, innerDispatch),
          onClose: (_) {},
        );
      });
    });
  });

  tearDown(() async {
    await server.close(force: true);
    appDb.close();
  });

  Future<_WsSession> connect() async {
    final ws = await WebSocket.connect('ws://127.0.0.1:$port');
    return _WsSession(ws);
  }

  test('без auth → not_authed, сокет жив', () async {
    final s = await connect();
    s.send({'type': 'create_room'});
    final msg = await s.next();
    expect(msg['type'], 'error');
    expect(msg['message'], 'not_authed');
    expect(s.closeCode, isNull);
    await s.close();
  });

  test('auth с битым токеном → bad_token + закрытие', () async {
    final s = await connect();
    s.send({'type': 'auth', 'token': 'invalid_token_xyz'});
    final msg = await s.next();
    expect(msg['type'], 'error');
    expect(msg['message'], 'bad_token');
    await s.waitClosed();
    expect(s.closeCode, isNotNull);
  });

  test('корректный auth → auth_ok, затем create_room → room_joined', () async {
    final s = await connect();
    s.send({'type': 'auth', 'token': validToken});
    final authOk = await s.next();
    expect(authOk['type'], 'auth_ok');
    expect(authOk['username'], 'TestUser');

    s.send({'type': 'create_room'});
    final msgs = <Map<String, dynamic>>[];
    // collect up to 2 messages
    for (var i = 0; i < 2; i++) {
      msgs.add(await s.next());
    }
    expect(msgs.any((m) => m['type'] == 'room_joined'), isTrue);
    await s.close();
  });

  test('нет сообщений → через ~5 сек auth_timeout', () async {
    final s = await connect();
    final msg =
        await s.next(timeout: const Duration(seconds: 7));
    expect(msg['type'], 'error');
    expect(msg['message'], 'auth_timeout');
    await s.waitClosed(timeout: const Duration(seconds: 2));
    expect(s.closeCode, isNotNull);
  }, timeout: const Timeout(Duration(seconds: 12)));
}
