import 'dart:async';
import 'dart:convert';
import 'dart:io';

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
