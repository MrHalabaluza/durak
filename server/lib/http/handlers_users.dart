import 'dart:io';
import '../db/models.dart';
import '../db/stats_dao.dart';
import '../db/user_dao.dart';
import 'handlers_me.dart' show statsJson;
import 'json_io.dart';

Future<void> handleGetUser(HttpRequest req, Map<String, String> params,
    UserDao users, StatsDao stats) async {
  final id = int.tryParse(params['id']!);
  if (id == null) return writeError(req, 400, 'invalid_id', '');
  final u = users.findById(id);
  if (u == null) return writeError(req, 404, 'user_not_found', '');
  final s = stats.getUserStats(id) ?? const UserStatsRow(0, 0, 0, 0, 0, null);
  writeJson(req, {
    'user': {
      'id': u.id,
      'username': u.username,
      'avatar_url': u.avatarPath == null ? null : '/${u.avatarPath}',
      'created_at': u.createdAt,
    },
    'stats': statsJson(s),
  });
}
