# TODO: Регистрация, авторизация и статистика игроков

> Документ-руководство для реализации фичи «учётные записи + статистика» в проекте DTFool. Каждый шаг — отдельный коммит, проходящий сборку и тесты. Реализуй шаги строго по порядку. Цитируемые номера строк актуальны на момент составления плана; перед правкой свериться с фактическим содержимым файлов.

---

## 0. Контекст проекта

**DTFool** — карточная игра «Двойной переводной дурак». Монорепо с тремя модулями:

- `logic/` — pure Dart-библиотека правил игры, без I/O. **Не трогать.**
- `server/` — WebSocket-сервер на Dart, единственная зависимость — `durak_logic` через path. Сейчас полностью stateless: каждое подключение получает random hex `playerId`, никнейм передаётся клиентом, ничего не сохраняется.
- `ui/` — Flutter-клиент. Зависит от `web_socket_channel`, `shared_preferences`, `flutter_animate`, `durak_logic`.

Завершение игры в `logic/lib/src/game_state.dart`: при `phase == GamePhase.finished` поле `loserId: String?` равно `null` для ничьей или `id` проигравшего игрока. Сервер ловит это в [server/lib/room.dart:80-90](server/lib/room.dart#L80) — это **единственная точка фиксации статистики**.

### Цели

1. Регистрация и логин с паролем (логин принимает кириллицу).
2. Пароль не передаётся в открытом виде.
3. Статистика игрока: партии, победы, поражения, винрейт.
4. Статистика сервера: лидерборд (с сортировкой) + общее число партий.
5. Загрузка аватарки.
6. Хранение в SQL на отдельном Docker volume.
7. Минимальная связность с существующим игровым кодом.

### Принятые решения (НЕ обсуждать заново)

| Тема | Решение |
|---|---|
| Гостевая игра | Запрещена. Любой WS-сокет без `auth` отвергается. |
| SQL-движок | SQLite (пакет `sqlite3` для Dart, синхронный native binding) |
| Хеш пароля | Клиент: `sha256("$username:$password")` (hex). Сервер: `argon2id` поверх. |
| Аватарки | Файлы на volume `/data/avatars/<userId>.<ext>`, путь в БД |
| WS-auth | Первое сообщение `{type:"auth", token}`. Idle 5 сек без auth → close |
| Никнейм | = `username`. Username неизменяем в первой версии |
| REST-транспорт | На том же `HttpServer`, что и WS (`/api/...`, `/avatars/...`) |
| Token storage в UI | `flutter_secure_storage` (Keychain/Keystore). Профильные поля — `shared_preferences` |
| Хранение статы | Денормализованная `user_stats` + историческая `games`/`game_players` |
| HTTP router | Свой минимальный (10 эндпоинтов, `shelf` не тянем) |
| Argon2-пакет | `hashlib` (pure Dart) — fallback на `argon2` если в `hashlib` нет нужного API |

---

## Pre-requisites

Должен быть установлен:
- Dart SDK ≥ 3.0
- Flutter SDK совместимый с `ui/pubspec.yaml`
- Docker и docker-compose (для smoke-тестов)
- `websocat` или аналог для ручной проверки WS

---

## Шаг 1 — Схема БД и DAO

**Цель:** добавить SQLite-зависимость, реализовать миграцию v1, написать DAO для users/sessions/stats.

### 1.1. Зависимости сервера

В `server/pubspec.yaml` добавить:

```yaml
dependencies:
  durak_logic:
    path: ../logic
  sqlite3: ^2.4.0
  crypto: ^3.0.3
  hashlib: ^1.19.0       # argon2id; если не подойдёт — argon2: ^1.0.1
  mime: ^1.0.5

dev_dependencies:
  test: ^1.24.0
```

Запустить `cd server && dart pub get`.

### 1.2. Создать `server/lib/db/database.dart`

```dart
import 'dart:io';
import 'package:sqlite3/sqlite3.dart';
import 'migrations.dart';

class AppDatabase {
  final Database db;
  AppDatabase._(this.db);

  static AppDatabase open(String path) {
    final dir = File(path).parent;
    if (!dir.existsSync()) dir.createSync(recursive: true);
    final db = sqlite3.open(path);
    db.execute('PRAGMA foreign_keys = ON;');
    db.execute('PRAGMA journal_mode = WAL;');
    _runMigrations(db);
    return AppDatabase._(db);
  }

  static void _runMigrations(Database db) {
    int currentVersion = 0;
    final tableExists = db.select(
      "SELECT name FROM sqlite_master WHERE type='table' AND name='schema_version'",
    );
    if (tableExists.isNotEmpty) {
      final rows = db.select('SELECT version FROM schema_version');
      if (rows.isNotEmpty) currentVersion = rows.first['version'] as int;
    }
    for (var i = currentVersion; i < migrations.length; i++) {
      db.execute('BEGIN');
      try {
        db.execute(migrations[i]);
        db.execute('DELETE FROM schema_version');
        db.execute('INSERT INTO schema_version VALUES (?)', [i + 1]);
        db.execute('COMMIT');
      } catch (e) {
        db.execute('ROLLBACK');
        rethrow;
      }
    }
  }

  void close() => db.dispose();
}
```

### 1.3. Создать `server/lib/db/migrations.dart`

```dart
const List<String> migrations = [
  // v1 — initial schema
  '''
  CREATE TABLE users (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    username        TEXT    NOT NULL,
    username_lower  TEXT    NOT NULL UNIQUE,
    password_hash   TEXT    NOT NULL,
    avatar_path     TEXT,
    created_at      INTEGER NOT NULL
  );
  CREATE INDEX idx_users_username_lower ON users(username_lower);

  CREATE TABLE sessions (
    token       TEXT PRIMARY KEY,
    user_id     INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    created_at  INTEGER NOT NULL,
    last_seen   INTEGER NOT NULL
  );
  CREATE INDEX idx_sessions_user ON sessions(user_id);

  CREATE TABLE games (
    id            INTEGER PRIMARY KEY AUTOINCREMENT,
    room_id       TEXT NOT NULL,
    started_at    INTEGER NOT NULL,
    finished_at   INTEGER NOT NULL,
    player_count  INTEGER NOT NULL,
    outcome       TEXT NOT NULL CHECK (outcome IN ('loss','draw')),
    loser_user_id INTEGER REFERENCES users(id)
  );
  CREATE INDEX idx_games_finished_at ON games(finished_at DESC);

  CREATE TABLE game_players (
    game_id INTEGER NOT NULL REFERENCES games(id) ON DELETE CASCADE,
    user_id INTEGER NOT NULL REFERENCES users(id),
    result  TEXT NOT NULL CHECK (result IN ('win','loss','draw')),
    PRIMARY KEY (game_id, user_id)
  );
  CREATE INDEX idx_game_players_user ON game_players(user_id);

  CREATE TABLE user_stats (
    user_id        INTEGER PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
    games_played   INTEGER NOT NULL DEFAULT 0,
    wins           INTEGER NOT NULL DEFAULT 0,
    losses         INTEGER NOT NULL DEFAULT 0,
    draws          INTEGER NOT NULL DEFAULT 0,
    last_played_at INTEGER
  );
  CREATE INDEX idx_user_stats_wins  ON user_stats(wins DESC);
  CREATE INDEX idx_user_stats_games ON user_stats(games_played DESC);
  CREATE INDEX idx_user_stats_winrate
    ON user_stats(((wins * 1.0) / NULLIF(games_played, 0)) DESC);

  CREATE TABLE server_stats (
    id          INTEGER PRIMARY KEY CHECK (id = 1),
    total_games INTEGER NOT NULL DEFAULT 0,
    total_users INTEGER NOT NULL DEFAULT 0
  );
  INSERT INTO server_stats (id, total_games, total_users) VALUES (1, 0, 0);

  CREATE TABLE schema_version (version INTEGER PRIMARY KEY);
  ''',
];
```

> **Важно:** `sqlite3.execute` поддерживает несколько SQL-стейтментов в одной строке через `;`.

### 1.4. Создать `server/lib/db/models.dart`

Простые data-классы (`UserRow`, `UserStatsRow`, `LeaderboardItem`, `SessionRow`). Каждый имеет `factory fromRow(Row row)`.

### 1.5. Создать DAO-файлы

- `server/lib/db/user_dao.dart`:
  - `int create({required String username, required String passwordHash})` — INSERT users + INSERT user_stats(user_id, 0,0,0,0,NULL) + UPDATE server_stats.total_users; возвращает id.
  - `UserRow? findById(int id)`, `UserRow? findByUsernameLower(String lower)`.
  - `void updateAvatarPath(int userId, String? path)`.

- `server/lib/db/session_dao.dart`:
  - `String create(int userId)` — генерирует 32 байта `Random.secure()` → base64url, INSERT sessions, возвращает token.
  - `SessionRow? find(String token)`.
  - `void delete(String token)`.
  - `void touch(String token)` — обновляет `last_seen`.

- `server/lib/db/stats_dao.dart`:
  - `UserStatsRow? getUserStats(int userId)`.
  - `({int totalGames, int totalUsers}) getServerStats()`.
  - `({int total, List<LeaderboardItem> items}) getLeaderboard({required String sort, required String order, required int limit, required int offset})`. **`sort`/`order` ВАЛИДИРУЮТСЯ через whitelist** — собирай SQL только если значение в whitelist'е, иначе кидай `ArgumentError`.
    Whitelist: `{'wins', 'games_played', 'winrate', 'losses', 'draws', 'last_played_at'}`. Order: `{'asc', 'desc'}`.
    Для `winrate` использовать `((wins * 1.0) / NULLIF(games_played, 0))` с `NULLS LAST`.
  - `void recordGame({required String roomId, required DateTime startedAt, required DateTime finishedAt, required List<int> participantUserIds, required int? loserUserId})`:
    1. `BEGIN TRANSACTION`.
    2. `INSERT INTO games(...)` с `outcome` = `'draw'` если `loserUserId == null`, иначе `'loss'`.
    3. Для каждого `userId` в `participantUserIds`: `INSERT INTO game_players(game_id, user_id, result)`. Result: `'draw'` если ничья, иначе `'loss'` для `loserUserId`, `'win'` для остальных.
    4. Для каждого: `UPDATE user_stats SET games_played = games_played + 1, wins = wins + ?, losses = losses + ?, draws = draws + ?, last_played_at = ? WHERE user_id = ?`.
    5. `UPDATE server_stats SET total_games = total_games + 1 WHERE id = 1`.
    6. `COMMIT`. На любой ошибке — `ROLLBACK; rethrow;`.

### 1.6. Тест `server/test/stats_dao_test.dart`

```dart
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
    stats.recordGame(roomId: 'R', startedAt: DateTime.now(), finishedAt: DateTime.now(),
        participantUserIds: [a, b], loserUserId: b);
    final lb = stats.getLeaderboard(sort: 'winrate', order: 'desc', limit: 50, offset: 0);
    expect(lb.items.first.user.id, a);
    expect(lb.items.last.user.id, c);  // нулевые партии — в конец
  });

  test('sort whitelist отбрасывает мусор', () {
    expect(() => stats.getLeaderboard(sort: 'username; DROP TABLE users', order: 'desc', limit: 10, offset: 0),
        throwsArgumentError);
  });
}
```

**Acceptance:** `cd server && dart test test/stats_dao_test.dart` — всё зелёное.

---

## Шаг 2 — Argon2 + AuthService

**Цель:** изолированный сервис, отвечающий за регистрацию/логин/токены, без HTTP-обёртки.

### 2.1. `server/lib/auth/password.dart`

```dart
import 'dart:typed_data';
import 'dart:math';
import 'package:hashlib/hashlib.dart';

class PasswordHasher {
  static String hash(String clientHashHex) {
    final salt = _randomBytes(16);
    final argon = Argon2Security.little; // ИЛИ moderate, см. ниже
    final h = argon2id(
      Uint8List.fromList(clientHashHex.codeUnits),
      salt,
      security: argon,
    );
    return h.encoded(); // PHC encoded строка
  }

  static bool verify(String clientHashHex, String storedEncoded) {
    return argon2Verify(storedEncoded, Uint8List.fromList(clientHashHex.codeUnits));
  }

  static Uint8List _randomBytes(int n) {
    final r = Random.secure();
    return Uint8List.fromList(List.generate(n, (_) => r.nextInt(256)));
  }
}
```

> Если `hashlib` API окажется другим — свериться с `pub.dev/packages/hashlib`. Если совсем не подойдёт — fallback на пакет `argon2` с похожим API. **Параметры argon2id — moderate** (минимум t=2, m=19MB, p=1).

### 2.2. `server/lib/auth/auth_service.dart`

```dart
class AuthService {
  final UserDao _users;
  final SessionDao _sessions;
  AuthService(this._users, this._sessions);

  /// Возвращает (userId, token) при успехе.
  ({int userId, String username, String token, String? avatarPath}) register({
    required String username,
    required String clientPasswordHash,
  }) {
    final usernameValidated = _validateUsername(username);
    final lower = usernameValidated.toLowerCase();
    if (_users.findByUsernameLower(lower) != null) {
      throw AuthException('username_taken', 'Username already in use');
    }
    final stored = PasswordHasher.hash(clientPasswordHash);
    final id = _users.create(username: usernameValidated, passwordHash: stored);
    final token = _sessions.create(id);
    return (userId: id, username: usernameValidated, token: token, avatarPath: null);
  }

  ({int userId, String username, String token, String? avatarPath}) login({
    required String username,
    required String clientPasswordHash,
  }) {
    final user = _users.findByUsernameLower(username.toLowerCase());
    if (user == null) throw AuthException('bad_credentials', 'Bad credentials');
    if (!PasswordHasher.verify(clientPasswordHash, user.passwordHash)) {
      throw AuthException('bad_credentials', 'Bad credentials');
    }
    final token = _sessions.create(user.id);
    return (userId: user.id, username: user.username, token: token, avatarPath: user.avatarPath);
  }

  void logout(String token) => _sessions.delete(token);

  UserRow? resolveToken(String token) {
    final s = _sessions.find(token);
    if (s == null) return null;
    _sessions.touch(token);
    return _users.findById(s.userId);
  }

  static String _validateUsername(String input) {
    final trimmed = input.trim();
    final re = RegExp(r'^[\p{L}\p{N}_.\- ]{1,32}$', unicode: true);
    if (!re.hasMatch(trimmed)) {
      throw AuthException('invalid_username', 'Invalid username format');
    }
    return trimmed;
  }
}

class AuthException implements Exception {
  final String code;
  final String message;
  AuthException(this.code, this.message);
}
```

### 2.3. Тест `server/test/auth_test.dart`

Кейсы:
- `register('Вася', hashOf('Вася', '123'))` → ok; повтор → `username_taken`.
- `register('Вася ')` (с пробелом) → trim, ок; следующий `register('вася')` → `username_taken`.
- `register('!!!')` → `invalid_username`.
- `login('Вася', hashOf('Вася', '123'))` → ok, токен НЕ совпадает с регистрационным.
- `login('Вася', hashOf('Вася', 'wrong'))` → `bad_credentials`.
- `resolveToken(token)` → user; после `logout(token)` → null.

**Acceptance:** `dart test test/auth_test.dart` зелёный.

---

## Шаг 3 — REST endpoints (register/login/logout/me)

**Цель:** HTTP-роутер на голом `dart:io` + три первых эндпоинта.

### 3.1. `server/lib/http/json_io.dart`

```dart
Future<Map<String, dynamic>> readJsonBody(HttpRequest req) async {
  final raw = await utf8.decoder.bind(req).join();
  if (raw.isEmpty) return {};
  return jsonDecode(raw) as Map<String, dynamic>;
}

void writeJson(HttpRequest req, Object body, {int status = 200}) {
  req.response
    ..statusCode = status
    ..headers.contentType = ContentType('application', 'json', charset: 'utf-8')
    ..write(jsonEncode(body));
  unawaited(req.response.close());
}

void writeError(HttpRequest req, int status, String code, String message) =>
    writeJson(req, {'error': code, 'message': message}, status: status);
```

### 3.2. `server/lib/http/router.dart`

Минимальный path-router: список троек `(method, pattern, handler)`. Pattern — строка вида `/api/users/:id`. Совпадение — обычный split по `/`, сегмент с `:` — параметр.

```dart
typedef HttpHandler = Future<void> Function(HttpRequest req, Map<String, String> params);

class Route {
  final String method;
  final List<String> segments;
  final HttpHandler handler;
  Route(this.method, String pattern, this.handler)
      : segments = pattern.split('/').where((s) => s.isNotEmpty).toList();

  Map<String, String>? match(String method, List<String> reqSegs) {
    if (method != this.method) return null;
    if (reqSegs.length != segments.length) return null;
    final params = <String, String>{};
    for (var i = 0; i < segments.length; i++) {
      if (segments[i].startsWith(':')) {
        params[segments[i].substring(1)] = reqSegs[i];
      } else if (segments[i] != reqSegs[i]) {
        return null;
      }
    }
    return params;
  }
}

class Router {
  final List<Route> _routes = [];
  void add(String method, String pattern, HttpHandler h) =>
      _routes.add(Route(method, pattern, h));

  /// true если запрос обработан, false иначе (например, ws-апгрейд).
  Future<bool> dispatch(HttpRequest req) async {
    final segs = req.uri.pathSegments;
    for (final r in _routes) {
      final p = r.match(req.method, segs);
      if (p != null) { await r.handler(req, p); return true; }
    }
    return false;
  }
}
```

### 3.3. Auth-helper для HTTP

В `server/lib/http/server_http.dart` (или отдельном файле):

```dart
UserRow? authedUser(HttpRequest req, AuthService auth) {
  final h = req.headers.value('authorization');
  if (h == null || !h.startsWith('Bearer ')) return null;
  return auth.resolveToken(h.substring(7));
}
```

### 3.4. Хендлеры — `server/lib/http/handlers_auth.dart`

```dart
Future<void> handleRegister(HttpRequest req, AuthService auth) async {
  final body = await readJsonBody(req);
  final username = body['username'] as String?;
  final passwordHash = body['password_hash'] as String?;
  if (username == null || passwordHash == null || passwordHash.length != 64) {
    return writeError(req, 400, 'invalid_request', 'username and password_hash required');
  }
  try {
    final res = auth.register(username: username, clientPasswordHash: passwordHash);
    writeJson(req, {
      'token': res.token,
      'user': {'id': res.userId, 'username': res.username, 'avatar_url': null},
    }, status: 201);
  } on AuthException catch (e) {
    final status = e.code == 'username_taken' ? 409 : 400;
    writeError(req, status, e.code, e.message);
  }
}

Future<void> handleLogin(HttpRequest req, AuthService auth) async {
  final body = await readJsonBody(req);
  final username = body['username'] as String?;
  final passwordHash = body['password_hash'] as String?;
  if (username == null || passwordHash == null) {
    return writeError(req, 400, 'invalid_request', 'username and password_hash required');
  }
  try {
    final res = auth.login(username: username, clientPasswordHash: passwordHash);
    writeJson(req, {
      'token': res.token,
      'user': {
        'id': res.userId,
        'username': res.username,
        'avatar_url': res.avatarPath == null ? null : '/${res.avatarPath}',
      },
    });
  } on AuthException catch (e) {
    writeError(req, 401, e.code, e.message);
  }
}

Future<void> handleLogout(HttpRequest req, AuthService auth) async {
  final h = req.headers.value('authorization');
  if (h == null || !h.startsWith('Bearer ')) {
    return writeError(req, 401, 'unauthorized', 'Bearer token required');
  }
  auth.logout(h.substring(7));
  req.response.statusCode = 204;
  await req.response.close();
}
```

### 3.5. `server/lib/http/handlers_me.dart` (без аватарки пока)

`GET /api/me` — `authedUser(req, auth)`; если null → 401; иначе вернуть `{user, stats}`.

```dart
Future<void> handleGetMe(HttpRequest req, AuthService auth, StatsDao stats) async {
  final user = authedUser(req, auth);
  if (user == null) return writeError(req, 401, 'unauthorized', '');
  final s = stats.getUserStats(user.id) ??
      const UserStatsRow(0, 0, 0, 0, 0, null);
  writeJson(req, {
    'user': {
      'id': user.id,
      'username': user.username,
      'avatar_url': user.avatarPath == null ? null : '/${user.avatarPath}',
      'created_at': user.createdAt,
    },
    'stats': _statsJson(s),
  });
}

Map<String, dynamic> _statsJson(UserStatsRow s) => {
  'games_played': s.gamesPlayed,
  'wins': s.wins,
  'losses': s.losses,
  'draws': s.draws,
  'winrate': s.gamesPlayed == 0 ? null : s.wins / s.gamesPlayed,
  'last_played_at': s.lastPlayedAt,
};
```

### 3.6. Маршрутизация в `server/bin/server.dart`

Перед текущей проверкой `WebSocketTransformer.isUpgradeRequest` (строки 22-29) подключить router:

```dart
final db = AppDatabase.open(Platform.environment['DURAK_DB_PATH'] ?? '/data/durak.db');
final auth = AuthService(UserDao(db.db), SessionDao(db.db));
final stats = StatsDao(db.db);

final router = Router()
  ..add('POST', '/api/register', (r, _) => handleRegister(r, auth))
  ..add('POST', '/api/login',    (r, _) => handleLogin(r, auth))
  ..add('POST', '/api/logout',   (r, _) => handleLogout(r, auth))
  ..add('GET',  '/api/me',       (r, _) => handleGetMe(r, auth, stats));

await for (final request in server) {
  if (WebSocketTransformer.isUpgradeRequest(request)) {
    // ... existing WS upgrade ...
    continue;
  }
  if (await router.dispatch(request)) continue;
  request.response..statusCode = HttpStatus.notFound..close();
}
```

### 3.7. Тест `server/test/http_handlers_test.dart`

Запустить настоящий `HttpServer` на эфемерном порту, дернуть через `package:http` или `HttpClient`. Проверить:
- POST /api/register с валидным телом → 201, `token` непустой.
- POST /api/register повторно с тем же username → 409.
- POST /api/login с верным паролем → 200, `token`.
- POST /api/login с неверным паролем → 401.
- GET /api/me без токена → 401.
- GET /api/me с токеном → 200, корректный username.
- POST /api/logout → 204; следующий GET /api/me с тем же токеном → 401.

**Acceptance:** `dart test test/http_handlers_test.dart` зелёный, ручная проверка через `curl`:

```bash
curl -X POST http://localhost:8080/api/register \
  -H 'Content-Type: application/json' \
  -d '{"username":"Vasya","password_hash":"<sha256 hex>"}'
```

---

## Шаг 4 — WebSocket auth middleware

**Цель:** до `auth` все сообщения отвергаются, через 5 сек idle — close.

### 4.1. Расширить `server/lib/protocol.dart`

Добавить класс и ветку парсинга:

```dart
class AuthMsg extends ClientMessage {
  final String token;
  const AuthMsg(this.token);
}

// в ClientMessage.parse:
'auth' => AuthMsg(map['token'] as String),

// исходящее:
Map<String, dynamic> authOkMsg(int userId, String username) =>
    {'type': 'auth_ok', 'userId': userId.toString(), 'username': username};
```

### 4.2. Изменить `server/lib/connection.dart`

```dart
class Connection {
  final WebSocket _socket;
  String? playerId;       // = userId.toString() после auth
  String? username;
  bool authed = false;
  Room? room;
  String nickname = '';
  Timer? _authTimer;

  Connection({
    required WebSocket socket,
    required MessageHandler onMessage,
    required CloseHandler onClose,
  }) : _socket = socket {
    _authTimer = Timer(const Duration(seconds: 5), () {
      if (!authed) {
        send(errorMsg('auth_timeout'));
        close();
      }
    });
    socket.listen(
      (data) {
        if (data is! String) return;
        try {
          onMessage(this, ClientMessage.parse(data));
        } catch (e) {
          send(errorMsg('Bad message: $e'));
        }
      },
      onDone: () { _authTimer?.cancel(); onClose(this); },
      onError: (_) { _authTimer?.cancel(); onClose(this); },
      cancelOnError: false,
    );
  }

  void markAuthed(int userId, String username) {
    _authTimer?.cancel();
    authed = true;
    playerId = userId.toString();
    this.username = username;
    nickname = username;
  }
  // ... send/close без изменений ...
}
```

### 4.3. `server/lib/auth/ws_auth.dart`

```dart
typedef Dispatch = void Function(Connection conn, ClientMessage msg);

Dispatch authedDispatch(AuthService auth, Dispatch inner) {
  return (conn, msg) {
    if (!conn.authed) {
      if (msg is AuthMsg) {
        final u = auth.resolveToken(msg.token);
        if (u == null) {
          conn.send(errorMsg('bad_token'));
          conn.close();
          return;
        }
        conn.markAuthed(u.id, u.username);
        conn.send(authOkMsg(u.id, u.username));
      } else {
        conn.send(errorMsg('not_authed'));
      }
      return;
    }
    inner(conn, msg);
  };
}
```

### 4.4. Изменить `server/bin/server.dart` (ws-апгрейд)

Удалить `_newPlayerId()` и его использование. WS-обработчик:

```dart
WebSocketTransformer.upgrade(request).then((ws) {
  total++;
  final innerDispatch = (Connection conn, ClientMessage msg) {
    if (msg is CreateRoomMsg || msg is JoinRoomMsg ||
        msg is LeaveRoomMsg || msg is StartGameMsg) {
      handleLobby(conn, msg);
    } else if (msg is! AuthMsg) {
      handleGame(conn, msg);
    }
  };
  Connection(
    socket: ws,
    onMessage: authedDispatch(auth, innerDispatch),
    onClose: (conn) {
      total--;
      final room = conn.room;
      if (room != null) {
        room.removePlayer(conn);
        if (room.isEmpty) {
          RoomManager.instance.removeIfEmpty(room.id);
        } else if (conn.playerId != null) {
          room.broadcast({'type': 'player_left', 'playerId': conn.playerId});
        }
      }
    },
  );
});
```

### 4.5. Поправить `server/lib/handlers/lobby.dart`

- Удалить функцию `_resolveNickname` (БД теперь гарантирует уникальность).
- В `_create` и `_join`: `conn.nickname = conn.username!;` (вместо resolved).
- Поля `nickname` из msg игнорировать (но парсер оставить для совместимости).

### 4.6. Тест `server/test/ws_auth_test.dart`

Подключиться `WebSocket.connect`, проверить:
- Отправить `create_room` без auth → ответ `error: not_authed`, сокет жив.
- Отправить `auth` с битым токеном → `error: bad_token` + сокет закрывается.
- Отправить корректный `auth` → `auth_ok`. Затем `create_room` → `room_joined`.
- Открыть сокет, ничего не слать → через ~5 сек закрытие сервером (`error: auth_timeout`).

**Acceptance:** `curl` для register, затем `websocat ws://localhost:8080`, `{"type":"auth","token":"<token>"}` → `auth_ok`.

---

## Шаг 5 — Запись статистики при finished

**Цель:** в `Room._broadcastGameState()` ровно один раз вызывать `StatsDao.recordGame`.

### 5.1. Изменить `server/lib/room_manager.dart`

```dart
class RoomManager {
  static late RoomManager instance;
  static void init(StatsDao stats) { instance = RoomManager._(stats); }

  final StatsDao _stats;
  final Map<String, Room> _rooms = {};
  RoomManager._(this._stats);

  Room create() {
    final id = _generateId();
    final room = Room(id, _stats);
    _rooms[id] = room;
    return room;
  }
  // ... остальное без изменений ...
}
```

В `bin/server.dart` после создания `stats` вызывать `RoomManager.init(stats);`.

### 5.2. Изменить `server/lib/room.dart`

```dart
class Room {
  final String id;
  final StatsDao _stats;
  final List<Connection> _connections = [];
  Game? _game;
  DateTime? _startedAt;
  bool _finishedRecorded = false;

  Room(this.id, this._stats);

  bool startGame([DeckConfig? config]) {
    if (isStarted || _connections.length < 2) return false;
    _startedAt = DateTime.now();
    try {
      _game = Game.start(playerIds, config: config);
    } on GameException catch (e) {
      for (final c in _connections) c.send(errorMsg(e.message));
      return false;
    }
    _broadcastGameState();
    return true;
  }

  void _broadcastGameState() {
    final state = _game!.state;
    final addingIds = _game!.addingPlayerIds;
    final nicks = {for (final c in _connections) c.playerId!: c.nickname};
    for (final conn in _connections) {
      conn.send(gameStateMsg(state, conn.playerId!, addingIds, nicks));
    }
    if (state.phase == GamePhase.finished && !_finishedRecorded) {
      _finishedRecorded = true;
      try {
        _stats.recordGame(
          roomId: id,
          startedAt: _startedAt!,
          finishedAt: DateTime.now(),
          participantUserIds: _connections.map((c) => int.parse(c.playerId!)).toList(),
          loserUserId: state.loserId == null ? null : int.parse(state.loserId!),
        );
      } catch (e, st) {
        print('recordGame failed: $e\n$st');  // не валим broadcast
      }
      broadcast({'type': 'game_over', 'loserId': state.loserId});
    }
  }
  // остальное без изменений
}
```

### 5.3. Тест

Интеграционный, в `server/test/room_stats_test.dart`:
- Создать БД in-memory, два пользователя (id 1, 2).
- Создать `Room`, добавить два mock-Connection с `playerId='1'`, `'2'`.
- Запустить `room.startGame()`. Сыграть синтетически до финиша (через прямые вызовы `Game` методов или подменить `_game` на mock с `phase=finished, loserId='2'`).
- Дёрнуть `room._broadcastGameState()` дважды (для проверки `_finishedRecorded`).
- Проверить: ровно одна запись в `games`, две в `game_players`, `wins=1` у user 1, `losses=1` у user 2.

**Acceptance:** `dart test`.

---

## Шаг 6 — REST: users, leaderboard, server-stats

### 6.1. `server/lib/http/handlers_users.dart`

`GET /api/users/:id` — публичный профиль:

```dart
Future<void> handleGetUser(HttpRequest req, Map<String, String> params,
    UserDao users, StatsDao stats) async {
  final id = int.tryParse(params['id']!);
  if (id == null) return writeError(req, 400, 'invalid_id', '');
  final u = users.findById(id);
  if (u == null) return writeError(req, 404, 'user_not_found', '');
  final s = stats.getUserStats(id) ?? const UserStatsRow(0,0,0,0,0,null);
  writeJson(req, {
    'user': {'id': u.id, 'username': u.username,
             'avatar_url': u.avatarPath == null ? null : '/${u.avatarPath}',
             'created_at': u.createdAt},
    'stats': _statsJson(s),
  });
}
```

### 6.2. `server/lib/http/handlers_stats.dart`

```dart
const _allowedSort = {'wins', 'games_played', 'winrate', 'losses', 'draws', 'last_played_at'};
const _allowedOrder = {'asc', 'desc'};

Future<void> handleLeaderboard(HttpRequest req, StatsDao stats) async {
  final q = req.uri.queryParameters;
  final sort = q['sort'] ?? 'wins';
  final order = q['order'] ?? 'desc';
  final limit = int.tryParse(q['limit'] ?? '50')?.clamp(1, 200) ?? 50;
  final offset = int.tryParse(q['offset'] ?? '0') ?? 0;
  if (!_allowedSort.contains(sort) || !_allowedOrder.contains(order)) {
    return writeError(req, 400, 'invalid_query', 'sort/order outside whitelist');
  }
  final lb = stats.getLeaderboard(sort: sort, order: order, limit: limit, offset: offset);
  writeJson(req, {
    'total': lb.total,
    'items': lb.items.asMap().entries.map((e) => {
      'rank': offset + e.key + 1,
      'user': {'id': e.value.user.id, 'username': e.value.user.username,
               'avatar_url': e.value.user.avatarPath == null ? null : '/${e.value.user.avatarPath}'},
      'stats': _statsJson(e.value.stats),
    }).toList(),
  });
}

Future<void> handleServerStats(HttpRequest req, StatsDao stats, int onlineUsers) async {
  final s = stats.getServerStats();
  writeJson(req, {
    'total_games': s.totalGames,
    'total_users': s.totalUsers,
    'online_users': onlineUsers,
  });
}
```

`onlineUsers` — функция, возвращающая текущее число authed-соединений (взять из `RoomManager` или отдельного счётчика в `bin/server.dart`).

### 6.3. Маршруты в `bin/server.dart`

```dart
..add('GET',  '/api/users/:id',    (r, p) => handleGetUser(r, p, users, stats))
..add('GET',  '/api/leaderboard',  (r, _) => handleLeaderboard(r, stats))
..add('GET',  '/api/server-stats', (r, _) => handleServerStats(r, stats, _onlineCounter()))
```

### 6.4. Тесты

Расширить `http_handlers_test.dart`:
- Создать 3 пользователей, отыграть 2 партии. GET `/api/leaderboard?sort=wins` — порядок ожидаемый.
- Sort `password; DROP` → 400.
- GET `/api/users/9999` → 404.
- GET `/api/server-stats` — `total_games == 2`.

---

## Шаг 7 — Аватарки

### 7.1. `server/lib/http/multipart.dart`

Минимальный парсер `multipart/form-data` для одного файла-поля. Использовать `package:mime` для MIME-типов.

API:
```dart
class UploadedFile {
  final String fieldName;
  final String filename;
  final String contentType;
  final Uint8List bytes;
  UploadedFile(this.fieldName, this.filename, this.contentType, this.bytes);
}

Future<UploadedFile?> readSingleFile(HttpRequest req, {int maxBytes = 2 * 1024 * 1024}) async { ... }
```

Реализация: получить boundary из `Content-Type`, читать `req` как `Stream<List<int>>`, копить буфер, искать boundary, парсить headers (`Content-Disposition: form-data; name="file"; filename="..."`, `Content-Type: image/png`). При превышении `maxBytes` — кинуть исключение → 413.

### 7.2. Валидация magic bytes

```dart
String? detectImageExt(Uint8List bytes) {
  if (bytes.length < 12) return null;
  // PNG: 89 50 4E 47 0D 0A 1A 0A
  if (bytes[0]==0x89 && bytes[1]==0x50 && bytes[2]==0x4E && bytes[3]==0x47) return 'png';
  // JPEG: FF D8 FF
  if (bytes[0]==0xFF && bytes[1]==0xD8 && bytes[2]==0xFF) return 'jpg';
  // WebP: 52 49 46 46 ?? ?? ?? ?? 57 45 42 50
  if (bytes[0]==0x52 && bytes[1]==0x49 && bytes[2]==0x46 && bytes[3]==0x46 &&
      bytes[8]==0x57 && bytes[9]==0x45 && bytes[10]==0x42 && bytes[11]==0x50) return 'webp';
  return null;
}
```

### 7.3. `handlers_me.dart` — POST /api/me/avatar

```dart
Future<void> handleUploadAvatar(HttpRequest req, AuthService auth, UserDao users) async {
  final user = authedUser(req, auth);
  if (user == null) return writeError(req, 401, 'unauthorized', '');
  final UploadedFile? file;
  try {
    file = await readSingleFile(req);
  } on FormatException catch (e) {
    return writeError(req, 400, 'invalid_multipart', e.message);
  } on _TooLargeException {
    return writeError(req, 413, 'too_large', 'Max 2MB');
  }
  if (file == null) return writeError(req, 400, 'no_file', '');
  final ext = detectImageExt(file.bytes);
  if (ext == null) return writeError(req, 415, 'unsupported_type', '');

  final dir = Platform.environment['DURAK_AVATARS_DIR'] ?? '/data/avatars';
  Directory(dir).createSync(recursive: true);
  // удалить старый файл с другим расширением
  for (final e in ['png','jpg','webp']) {
    final old = File('$dir/${user.id}.$e');
    if (old.existsSync() && e != ext) old.deleteSync();
  }
  final out = File('$dir/${user.id}.$ext');
  out.writeAsBytesSync(file.bytes);
  final relPath = 'avatars/${user.id}.$ext';
  users.updateAvatarPath(user.id, relPath);
  writeJson(req, {'avatar_url': '/$relPath'});
}
```

### 7.4. `handlers_avatar.dart` — GET /avatars/:filename

```dart
Future<void> handleGetAvatar(HttpRequest req, Map<String, String> params) async {
  final fname = params['filename']!;
  if (fname.contains('/') || fname.contains('..') || fname.contains('\\')) {
    return writeError(req, 400, 'invalid_path', '');
  }
  final dir = Platform.environment['DURAK_AVATARS_DIR'] ?? '/data/avatars';
  final f = File('$dir/$fname');
  if (!f.existsSync()) return writeError(req, 404, 'not_found', '');
  final ext = fname.split('.').last;
  final ct = {'png':'image/png','jpg':'image/jpeg','webp':'image/webp'}[ext] ?? 'application/octet-stream';
  req.response
    ..statusCode = 200
    ..headers.contentType = ContentType.parse(ct)
    ..headers.set('Cache-Control', 'public, max-age=86400')
    ..add(f.readAsBytesSync());
  await req.response.close();
}
```

### 7.5. Маршруты

```dart
..add('POST', '/api/me/avatar',     (r, _) => handleUploadAvatar(r, auth, users))
..add('GET',  '/avatars/:filename', (r, p) => handleGetAvatar(r, p))
```

### 7.6. Тесты

- Загрузить настоящий PNG (4 байта magic + минимальный chunk) — 200.
- Загрузить файл с расширением .png но magic JPEG → должен сохраниться как `.jpg` (по magic).
- Загрузить TXT → 415.
- Загрузить 3 МБ → 413.
- GET /avatars/../etc/passwd → 400.
- GET /avatars/999.png (нет файла) → 404.

---

## Шаг 8 — Docker volume + distroless

### 8.1. Изменить `server/Dockerfile`

```dockerfile
FROM dart:stable AS build
WORKDIR /app/server
COPY logic/ /app/logic/
COPY server/pubspec.yaml server/pubspec.lock* ./
RUN dart pub get --no-example
COPY server/ ./
RUN dart compile exe bin/server.dart -o bin/server

# distroless вместо scratch — нужен libc для sqlite3
FROM gcr.io/distroless/cc-debian12
COPY --from=build /runtime/ /
COPY --from=build /app/server/bin/server /app/server
COPY --from=build /usr/lib/x86_64-linux-gnu/libsqlite3.so* /usr/lib/x86_64-linux-gnu/

VOLUME ["/data"]
EXPOSE 8080
ENV DURAK_DB_PATH=/data/durak.db
ENV DURAK_AVATARS_DIR=/data/avatars
ENTRYPOINT ["/app/server"]
```

> Если в build-образе нет `libsqlite3` — установить через `apt-get install -y libsqlite3-0` в stage `build`, либо использовать `sqlite3` пакет с bundled-режимом если поддерживается.

### 8.2. Создать `server/docker-compose.yaml`

```yaml
services:
  durak:
    build:
      context: ..
      dockerfile: server/Dockerfile
    ports:
      - "8080:8080"
    volumes:
      - durak-data:/data
    environment:
      - PORT=8080
      - DURAK_DB_PATH=/data/durak.db
      - DURAK_AVATARS_DIR=/data/avatars
volumes:
  durak-data:
```

### 8.3. Smoke-тест

```bash
docker compose -f server/docker-compose.yaml up --build -d
curl -X POST http://localhost:8080/api/register -H 'Content-Type: application/json' \
  -d '{"username":"smoke","password_hash":"<sha256>"}'
docker compose restart
curl -X POST http://localhost:8080/api/login -H 'Content-Type: application/json' \
  -d '{"username":"smoke","password_hash":"<sha256>"}'  # должен вернуть 200
```

---

## Шаг 9 — UI: api-клиент + login/register

### 9.1. Новые зависимости в `ui/pubspec.yaml`

```yaml
dependencies:
  flutter:
    sdk: flutter
  cupertino_icons: ^1.0.8
  shared_preferences: ^2.3.2
  web_socket_channel: ^3.0.2
  flutter_animate: ^4.5.0
  http: ^1.2.0
  crypto: ^3.0.3
  image_picker: ^1.1.2
  flutter_secure_storage: ^9.2.2
  cached_network_image: ^3.3.1
  durak_logic:
    path: ../logic
```

### 9.2. `ui/lib/auth/password_hash.dart`

```dart
import 'dart:convert';
import 'package:crypto/crypto.dart';

String clientPasswordHash(String username, String password) {
  final input = utf8.encode('$username:$password');
  return sha256.convert(input).toString(); // hex
}
```

### 9.3. `ui/lib/api/api_client.dart`

Базовый клиент: хранит `baseUrl`, `token`, делает GET/POST с правильными headers.

```dart
class ApiClient {
  final String baseUrl;     // http://host:port
  String? token;
  ApiClient(this.baseUrl, {this.token});

  Future<dynamic> get(String path) async {
    final r = await http.get(Uri.parse('$baseUrl$path'), headers: _headers());
    return _decode(r);
  }
  Future<dynamic> postJson(String path, Map<String,dynamic> body) async {
    final r = await http.post(Uri.parse('$baseUrl$path'),
        headers: {..._headers(), 'Content-Type': 'application/json'},
        body: jsonEncode(body));
    return _decode(r);
  }
  Future<dynamic> postMultipart(String path, String fieldName, Uint8List bytes,
      String filename, String contentType) async {
    final req = http.MultipartRequest('POST', Uri.parse('$baseUrl$path'))
      ..headers.addAll(_headers())
      ..files.add(http.MultipartFile.fromBytes(fieldName, bytes,
          filename: filename, contentType: MediaType.parse(contentType)));
    final r = await http.Response.fromStream(await req.send());
    return _decode(r);
  }
  Map<String,String> _headers() => token == null ? {} : {'Authorization': 'Bearer $token'};
  dynamic _decode(http.Response r) {
    if (r.statusCode == 204) return null;
    final body = r.body.isEmpty ? null : jsonDecode(r.body);
    if (r.statusCode >= 400) throw ApiException(r.statusCode, body?['error'] ?? 'http_$r.statusCode', body?['message'] ?? '');
    return body;
  }
}
class ApiException implements Exception { final int status; final String code; final String message;
  ApiException(this.status, this.code, this.message); }
```

### 9.4. Сервис-обёртки

- `ui/lib/api/auth_api.dart`: `register(username, passwordHash)`, `login(...)`, `logout()`.
- `ui/lib/api/me_api.dart`: `getMe()`, `uploadAvatar(bytes, filename, contentType)`.
- `ui/lib/api/users_api.dart`: `getUser(id)`.
- `ui/lib/api/stats_api.dart`: `getLeaderboard(sort, order, limit, offset)`, `getServerStats()`.

### 9.5. Изменить `ui/lib/app_settings.dart`

Удалить поле `playerName`. Добавить:
```dart
final String? token;       // в secure_storage
final int? userId;
final String? username;
final String? avatarUrl;   // относительный путь '/avatars/42.png'
```

Хранение: `token` через `FlutterSecureStorage`, остальное — `SharedPreferences`. Методы:
```dart
static Future<AppSettings> load() async {
  // читаем prefs + secure_storage параллельно
}
Future<void> saveAuth({required String token, required int userId,
                       required String username, String? avatarUrl}) async { ... }
Future<void> clearAuth() async { ... }
```

`baseHttpUrl` геттер: `'${tls?'https':'http'}://$serverHost:$serverPort'`.

### 9.6. Экраны auth

- `ui/lib/auth/auth_gate_screen.dart` — две вкладки (Tab) или две кнопки → `LoginScreen` или `RegisterScreen`.
- `ui/lib/auth/login_screen.dart`:
  - 2 поля: username, password.
  - Кнопка «Войти» → `clientPasswordHash(username, password)` → `AuthApi.login` → `AppSettings.saveAuth` → `Navigator.pushReplacement(SetupScreen)`.
  - Ошибки 401/400 показывать снэк-баром.
- `ui/lib/auth/register_screen.dart`:
  - Поля: username, password, password2.
  - Локальная проверка password == password2 (UX, не security).
  - Дальше как login, но через `AuthApi.register`.

### 9.7. Изменить `ui/lib/main.dart`

В `MyApp.build` или на старте `SetupScreen.initState`:
```dart
final settings = await AppSettings.load();
if (settings.token == null) {
  Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => AuthGateScreen()));
}
```

Иконку «Профиль» (FAB или AppBar action) добавить в `SetupScreen`.

### 9.8. Изменить `ui/lib/settings_screen.dart`

Удалить секцию «Имя игрока» — никнейм больше не редактируется здесь.

### 9.9. Smoke-тест шага 9

`flutter run`, без сервера авторизация падает с понятной ошибкой; с сервером — register и login работают.

---

## Шаг 10 — UI: WS-auth в LobbyScreen

### 10.1. Изменить `ui/lib/lobby_screen.dart`

В конструкторе принимать `token` (из `AppSettings`). В `_connect()`, сразу после `await ws.ready` и до отправки `create_room`/`join_room`:

```dart
_send({'type': 'auth', 'token': widget.token});
// Ждём auth_ok в _onMessage перед тем, как отправлять create_room/join_room.
```

В `_onMessage`:
```dart
if (msg['type'] == 'auth_ok') {
  // теперь шлём create_room или join_room
  if (widget.joinRoomId == null) {
    _send({'type':'create_room'});
  } else {
    _send({'type':'join_room', 'roomId': widget.joinRoomId});
  }
}
if (msg['type'] == 'error' && msg['message'] == 'bad_token') {
  await AppSettings.clearAuth();
  if (mounted) Navigator.pushReplacementToAuth(context);
}
```

UI должен показывать «Авторизация…» пока не пришёл `auth_ok`.

### 10.2. Acceptance шага 10

E2E: register → создать комнату → старт игры. Стол отрисовывается, играть можно.

---

## Шаг 11 — UI: профиль, лидерборд, аватарка

### 11.1. `ui/lib/profile/profile_screen.dart`

Открывается из `SetupScreen`. Показывает:
- Аватарку (через `cached_network_image`, key = `username:updated_marker`).
- Никнейм.
- Карточки статистики (см. ниже).
- Кнопку «Сменить аватарку» → `image_picker.pickImage(maxWidth: 512)` → `MeApi.uploadAvatar` → обновить `AppSettings.avatarUrl`.
- Кнопку «Выйти» → `AuthApi.logout()` → `AppSettings.clearAuth()` → редирект на `AuthGateScreen`.

### 11.2. `ui/lib/profile/stats_widgets.dart`

Виджеты:
- `StatsCardGrid({games, wins, losses, draws, winrate})` — 4 плитки.
- `WinrateBadge(winrate)` — `winrate == null ? '—' : '${(winrate*100).toStringAsFixed(1)}%'`.

### 11.3. `ui/lib/profile/leaderboard_screen.dart`

- DropDown для выбора `sort` (wins / games_played / winrate / losses / draws).
- `ListView.builder` с пагинацией (`offset += 50` при scroll-to-end).
- Каждая строка — `ListTile` с аватаркой, ником, основной метрикой, тапом → `UserProfileScreen`.
- В AppBar — `total` партий и пользователей (через `StatsApi.getServerStats`).

### 11.4. `ui/lib/profile/user_profile_screen.dart`

Принимает `userId`, грузит `UsersApi.getUser(id)`, отображает аватар + статистику. Никаких приватных действий.

### 11.5. Регистрация роутов

В `SetupScreen` добавить кнопки/иконки:
- «Профиль» → `ProfileScreen`.
- «Лидерборд» → `LeaderboardScreen`.

### 11.6. Acceptance шага 11

End-to-end:
1. Зарегистрировать двух пользователей с двух эмуляторов.
2. Сыграть партию.
3. Открыть `ProfileScreen` — статы обновились (1 партия, 1 победа или поражение).
4. Открыть `LeaderboardScreen`, выбрать sort=`winrate` — победитель сверху.
5. Загрузить аватарку, обновить экран — отрисовалась.
6. Logout, login другим аккаунтом — данные другие.
7. Перезапустить контейнер сервера (`docker compose restart`) — данные сохранились.

---

## Финальная верификация

```bash
cd logic  && dart test
cd server && dart pub get && dart test
cd ui     && flutter pub get && flutter test
docker compose -f server/docker-compose.yaml up --build
```

Ручной полный сценарий:

1. `flutter run` — попадаем на `AuthGateScreen`.
2. Регистрация `Вася` (юникод) — успех, попадаем на `SetupScreen`.
3. Открыть профиль — 0/0/0/0, аватар — placeholder.
4. На втором эмуляторе — регистрация `Петя`.
5. Вася создаёт комнату, делится кодом, Петя присоединяется.
6. Доиграть до конца партии.
7. Профиль Васи: 1/1/0/0, профиль Пети: 1/0/1/0 (или наоборот в зависимости от исхода).
8. Лидерборд по wins — Вася выше Пети.
9. Загрузить аватарку — отрисовалась.
10. Logout, попасть обратно на `AuthGateScreen`.
11. Через `websocat` отправить `{"type":"create_room"}` без auth → `error: not_authed`, через 5 сек close.
12. `docker compose restart` — все данные на месте.

---

## Замечания для исполнителя

- **Никаких изменений в `logic/`.** Если кажется, что нужно — это сигнал что что-то идёт не так.
- **`Room.recordGame` вызывается ровно один раз** благодаря флагу `_finishedRecorded`. Не убирай его.
- **`sort`/`order` всегда через whitelist.** Никогда не интерполируй пользовательский ввод в SQL.
- **Sqlite3 синхронный** — это намеренно, чтобы не таскать `await` через `Room`/`Game`.
- **Argon2 параметры** — moderate (m≥19MB, t≥2). Для тестов можно little (быстрее), но в production сборке — moderate.
- **Token** генерируется только через `Random.secure()`, не `Random()`.
- **Пароль на клиент пустой** — без длины и сложности (по требованиям). Проверять только что не пустой.
- **Username regex** — `^[\p{L}\p{N}_.\- ]{1,32}$` с unicode-флагом. Проверь на `Вася`, `Иван-Петров`, `Player_42`.
- При любом обновлении схемы БД — добавь новый элемент в `migrations` и **никогда** не редактируй существующие записи.
- Если build distroless ломается на отсутствии `libsqlite3` — переключись на `gcr.io/distroless/cc-debian12:latest` или `debian:stable-slim` с `apt-get install libsqlite3-0`.

## Критические файлы

- [server/bin/server.dart](server/bin/server.dart)
- [server/lib/room.dart](server/lib/room.dart)
- [server/lib/connection.dart](server/lib/connection.dart)
- [server/lib/protocol.dart](server/lib/protocol.dart)
- [server/lib/handlers/lobby.dart](server/lib/handlers/lobby.dart)
- [server/lib/room_manager.dart](server/lib/room_manager.dart)
- [server/Dockerfile](server/Dockerfile)
- [ui/lib/main.dart](ui/lib/main.dart)
- [ui/lib/lobby_screen.dart](ui/lib/lobby_screen.dart)
- [ui/lib/app_settings.dart](ui/lib/app_settings.dart)
- [ui/lib/settings_screen.dart](ui/lib/settings_screen.dart)
- [ui/pubspec.yaml](ui/pubspec.yaml)
- [server/pubspec.yaml](server/pubspec.yaml)
