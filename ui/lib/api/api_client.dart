import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

class ApiException implements Exception {
  final int status;
  final String code;
  final String message;
  ApiException(this.status, this.code, this.message);

  @override
  String toString() => 'ApiException($status, $code): $message';
}

class ApiClient {
  final String baseUrl;
  String? token;

  ApiClient(this.baseUrl, {this.token});

  Future<dynamic> get(String path) async {
    final r = await http.get(Uri.parse('$baseUrl$path'), headers: _headers());
    return _decode(r);
  }

  Future<dynamic> postJson(String path, Map<String, dynamic> body) async {
    final r = await http.post(
      Uri.parse('$baseUrl$path'),
      headers: {..._headers(), 'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );
    return _decode(r);
  }

  Future<dynamic> postMultipart(
    String path,
    String fieldName,
    Uint8List bytes,
    String filename,
    String contentType,
  ) async {
    final req = http.MultipartRequest('POST', Uri.parse('$baseUrl$path'))
      ..headers.addAll(_headers())
      ..files.add(http.MultipartFile.fromBytes(
        fieldName,
        bytes,
        filename: filename,
        contentType: MediaType.parse(contentType),
      ));
    final r = await http.Response.fromStream(await req.send());
    return _decode(r);
  }

  Map<String, String> _headers() =>
      token == null ? {} : {'Authorization': 'Bearer $token'};

  dynamic _decode(http.Response r) {
    if (r.statusCode == 204) return null;
    final body = r.body.isEmpty ? null : jsonDecode(r.body);
    if (r.statusCode >= 400) {
      throw ApiException(
        r.statusCode,
        body?['error'] as String? ?? 'http_${r.statusCode}',
        body?['message'] as String? ?? '',
      );
    }
    return body;
  }
}
