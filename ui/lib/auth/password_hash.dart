import 'dart:convert';
import 'package:crypto/crypto.dart';

String clientPasswordHash(String username, String password) {
  final input = utf8.encode('$username:$password');
  return sha256.convert(input).toString();
}
