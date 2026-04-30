import 'dart:io';
import '../auth/auth_service.dart';
import '../db/models.dart';
import '../db/stats_dao.dart';
import '../db/user_dao.dart';
import 'auth_helper.dart';
import 'json_io.dart';
import 'multipart.dart';

Future<void> handleGetMe(
    HttpRequest req, AuthService auth, StatsDao stats) async {
  final user = authedUser(req, auth);
  if (user == null) return writeError(req, 401, 'unauthorized', '');
  final s = stats.getUserStats(user.id) ??
      const UserStatsRow(0, 0, 0, 0, 0, null);
  writeJson(req, {
    'user': {
      'id': user.id,
      'username': user.username,
      'avatar_url':
          user.avatarPath == null ? null : '/${user.avatarPath}',
      'created_at': user.createdAt,
    },
    'stats': statsJson(s),
  });
}

Map<String, dynamic> statsJson(UserStatsRow s) => {
      'games_played': s.gamesPlayed,
      'wins': s.wins,
      'losses': s.losses,
      'draws': s.draws,
      'winrate':
          s.gamesPlayed == 0 ? null : s.wins / s.gamesPlayed,
      'last_played_at': s.lastPlayedAt,
    };

Future<void> handleUploadAvatar(
    HttpRequest req, AuthService auth, UserDao users, String avatarsDir) async {
  final user = authedUser(req, auth);
  if (user == null) return writeError(req, 401, 'unauthorized', '');

  final UploadedFile? file;
  try {
    file = await readSingleFile(req);
  } on FormatException catch (e) {
    return writeError(req, 400, 'invalid_multipart', e.message);
  } on TooLargeException {
    return writeError(req, 413, 'too_large', 'Max 2MB');
  }
  if (file == null) return writeError(req, 400, 'no_file', '');

  final ext = detectImageExt(file.bytes);
  if (ext == null) return writeError(req, 415, 'unsupported_type', '');

  Directory(avatarsDir).createSync(recursive: true);
  for (final e in ['png', 'jpg', 'webp']) {
    final old = File('$avatarsDir/${user.id}.$e');
    if (old.existsSync() && e != ext) old.deleteSync();
  }
  final out = File('$avatarsDir/${user.id}.$ext');
  out.writeAsBytesSync(file.bytes);
  final relPath = 'avatars/${user.id}.$ext';
  users.updateAvatarPath(user.id, relPath);
  writeJson(req, {'avatar_url': '/$relPath'});
}
