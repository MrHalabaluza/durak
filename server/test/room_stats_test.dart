import 'dart:io';
import 'package:durak_logic/durak_logic.dart';
import 'package:test/test.dart';
import 'package:durak_server/connection.dart';
import 'package:durak_server/room.dart';
import 'package:durak_server/db/database.dart';
import 'package:durak_server/db/user_dao.dart';
import 'package:durak_server/db/stats_dao.dart';

/// Creates a bare WebSocket pair via a local HTTP server upgrade.
/// Returns [Connection] objects with public fields ready to set.
Future<({Connection c1, Connection c2, HttpServer srv})> _makeConnections(
    StatsDao stats) async {
  final srv = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  final port = srv.port;

  final conns = <Connection>[];
  srv.listen((req) {
    if (WebSocketTransformer.isUpgradeRequest(req)) {
      WebSocketTransformer.upgrade(req).then((ws) {
        conns.add(Connection(
          socket: ws,
          onMessage: (_, __) {},
          onClose: (_) {},
        ));
      });
    }
  });

  // Connect two clients.
  await WebSocket.connect('ws://127.0.0.1:$port');
  await WebSocket.connect('ws://127.0.0.1:$port');

  // Wait for both server-side upgrades to complete.
  while (conns.length < 2) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }

  return (c1: conns[0], c2: conns[1], srv: srv);
}

void main() {
  late AppDatabase appDb;
  late UserDao users;
  late StatsDao stats;

  setUp(() {
    appDb = AppDatabase.open(':memory:');
    users = UserDao(appDb.db);
    stats = StatsDao(appDb.db);
  });

  tearDown(() => appDb.close());

  test('recordGame вызывается ровно один раз при finished', () async {
    final userId1 = users.create(username: 'Alice', passwordHash: 'x');
    final userId2 = users.create(username: 'Bob', passwordHash: 'x');

    final pair = await _makeConnections(stats);
    final c1 = pair.c1..playerId = userId1.toString()..nickname = 'Alice';
    final c2 = pair.c2..playerId = userId2.toString()..nickname = 'Bob';

    final room = Room('TESTROOM', stats);
    room.addPlayer(c1);
    room.addPlayer(c2);

    // Build a real 2-player game and mutate it into a finished state.
    final game = Game.start([userId1.toString(), userId2.toString()]);
    game.state.phase = GamePhase.finished;
    game.state.loserId = userId2.toString();

    room.injectGame(game, DateTime.now());

    // First broadcast — should record stats.
    room.broadcastGameState();
    // Second broadcast — should be a no-op (already recorded).
    room.broadcastGameState();

    final s1 = stats.getUserStats(userId1)!;
    final s2 = stats.getUserStats(userId2)!;
    expect(s1.wins, 1, reason: 'Alice won');
    expect(s1.losses, 0);
    expect(s2.losses, 1, reason: 'Bob lost');
    expect(s2.wins, 0);
    expect(stats.getServerStats().totalGames, 1,
        reason: 'exactly one game recorded');

    await pair.srv.close(force: true);
  });

  test('recordGame записывает ничью', () async {
    final a = users.create(username: 'A', passwordHash: 'x');
    final b = users.create(username: 'B', passwordHash: 'x');

    final pair = await _makeConnections(stats);
    pair.c1.playerId = a.toString();
    pair.c1.nickname = 'A';
    pair.c2.playerId = b.toString();
    pair.c2.nickname = 'B';

    final room = Room('DRAW', stats);
    room.addPlayer(pair.c1);
    room.addPlayer(pair.c2);

    final game = Game.start([a.toString(), b.toString()]);
    game.state.phase = GamePhase.finished;
    game.state.loserId = null; // draw

    room.injectGame(game, DateTime.now());
    room.broadcastGameState();

    expect(stats.getUserStats(a)!.draws, 1);
    expect(stats.getUserStats(b)!.draws, 1);
    expect(stats.getServerStats().totalGames, 1);

    await pair.srv.close(force: true);
  });
}
