import 'dart:io';
import 'package:sqlite3/sqlite3.dart';
import 'migrations.dart';

class AppDatabase {
  final Database db;
  AppDatabase._(this.db);

  static AppDatabase open(String path) {
    if (path != ':memory:') {
      final dir = File(path).parent;
      if (!dir.existsSync()) dir.createSync(recursive: true);
    }
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
