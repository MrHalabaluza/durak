import 'dart:io';
import '../auth/auth_service.dart';
import '../db/models.dart';

UserRow? authedUser(HttpRequest req, AuthService auth) {
  final h = req.headers.value('authorization');
  if (h == null || !h.startsWith('Bearer ')) return null;
  return auth.resolveToken(h.substring(7));
}
