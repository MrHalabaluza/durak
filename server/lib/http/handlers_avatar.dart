import 'dart:io';
import 'json_io.dart';

Future<void> handleGetAvatar(
    HttpRequest req, Map<String, String> params, String avatarsDir) async {
  final fname = params['filename']!;
  if (fname.contains('/') || fname.contains('..') || fname.contains('\\')) {
    return writeError(req, 400, 'invalid_path', '');
  }
  final f = File('$avatarsDir/$fname');
  if (!f.existsSync()) return writeError(req, 404, 'not_found', '');
  final ext = fname.split('.').last;
  final ct = {
        'png': 'image/png',
        'jpg': 'image/jpeg',
        'webp': 'image/webp',
      }[ext] ??
      'application/octet-stream';
  req.response
    ..statusCode = 200
    ..headers.contentType = ContentType.parse(ct)
    ..headers.set('Cache-Control', 'public, max-age=86400')
    ..add(f.readAsBytesSync());
  await req.response.close();
}
