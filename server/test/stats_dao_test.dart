import 'package:test/test.dart';
import 'package:durak_server/db/database.dart';
import 'package:durak_server/db/user_dao.dart';
import 'package:durak_server/db/stats_dao.dart';

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

  test('recordGame с проигравшим', () {
    final aId = users.create(username: 'A', passwordHash: 'x');
    final bId = users.create(username: 'B', passwordHash: 'x');
    stats.recordGame(
      roomId: 'R1',
      startedAt: DateTime.now(),
      finishedAt: DateTime.now(),
      participantUserIds: [aId, bId],
      loserUserId: bId,
    );
    final aStats = stats.getUserStats(aId)!;
    final bStats = stats.getUserStats(bId)!;
    expect(aStats.wins, 1);
    expect(aStats.losses, 0);
    expect(bStats.losses, 1);
    expect(stats.getServerStats().totalGames, 1);
  });

  test('recordGame ничья', () {
    final a = users.create(username: 'A', passwordHash: 'x');
    final b = users.create(username: 'B', passwordHash: 'x');
    stats.recordGame(
      roomId: 'R1',
      startedAt: DateTime.now(),
      finishedAt: DateTime.now(),
      participantUserIds: [a, b],
      loserUserId: null,
    );
    expect(stats.getUserStats(a)!.draws, 1);
    expect(stats.getUserStats(b)!.draws, 1);
  });

  test('лидерборд по winrate с NULLS LAST', () {
    final a = users.create(username: 'A', passwordHash: 'x');
    final b = users.create(username: 'B', passwordHash: 'x');
    final c = users.create(username: 'C', passwordHash: 'x'); // 0 games
    stats.recordGame(
      roomId: 'R',
      startedAt: DateTime.now(),
      finishedAt: DateTime.now(),
      participantUserIds: [a, b],
      loserUserId: b,
    );
    final lb = stats.getLeaderboard(
      sort: 'winrate',
      order: 'desc',
      limit: 50,
      offset: 0,
    );
    expect(lb.items.first.user.id, a);
    expect(lb.items.last.user.id, c);
  });

  test('sort whitelist отбрасывает мусор', () {
    expect(
      () => stats.getLeaderboard(
        sort: 'username; DROP TABLE users',
        order: 'desc',
        limit: 10,
        offset: 0,
      ),
      throwsArgumentError,
    );
  });
}
