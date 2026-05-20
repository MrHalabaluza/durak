const List<String> migrations = [
  // v1 — initial schema
  '''
  CREATE TABLE schema_version (version INTEGER PRIMARY KEY);

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

  CREATE TABLE server_stats (
    id          INTEGER PRIMARY KEY CHECK (id = 1),
    total_games INTEGER NOT NULL DEFAULT 0,
    total_users INTEGER NOT NULL DEFAULT 0
  );
  INSERT INTO server_stats (id, total_games, total_users) VALUES (1, 0, 0);
  ''',

  // v2 — per-user deck config storage
  '''
  CREATE TABLE user_decks (
    user_id     INTEGER PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
    deck_config TEXT    NOT NULL
  );
  ''',
];
