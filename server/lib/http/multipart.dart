import 'dart:io';
import 'dart:typed_data';

class UploadedFile {
  final String fieldName;
  final String filename;
  final String contentType;
  final Uint8List bytes;
  UploadedFile(this.fieldName, this.filename, this.contentType, this.bytes);
}

class TooLargeException implements Exception {}

Future<UploadedFile?> readSingleFile(HttpRequest req,
    {int maxBytes = 2 * 1024 * 1024}) async {
  final ct = req.headers.contentType;
  if (ct == null || ct.mimeType != 'multipart/form-data') {
    throw const FormatException('Expected multipart/form-data');
  }
  final boundary = ct.parameters['boundary'];
  if (boundary == null || boundary.isEmpty) {
    throw const FormatException('Missing boundary');
  }

  final buf = BytesBuilder(copy: false);
  await for (final chunk in req) {
    buf.add(chunk);
    if (buf.length > maxBytes) throw TooLargeException();
  }

  return _parse(buf.toBytes(), boundary);
}

UploadedFile? _parse(Uint8List data, String boundary) {
  final dash2 = '--$boundary'.codeUnits;
  final crlf4 = [13, 10, 13, 10]; // \r\n\r\n

  int pos = _indexOf(data, Uint8List.fromList(dash2), 0);
  if (pos < 0) throw const FormatException('No boundary found');
  pos += dash2.length;

  while (pos < data.length) {
    // After boundary: '--' means final, '\r\n' means part follows
    if (pos + 1 < data.length &&
        data[pos] == 0x2D &&
        data[pos + 1] == 0x2D) {
      break;
    }
    if (pos + 1 < data.length &&
        data[pos] == 0x0D &&
        data[pos + 1] == 0x0A) {
      pos += 2;
    } else {
      break;
    }

    final headerEnd =
        _indexOf(data, Uint8List.fromList(crlf4), pos);
    if (headerEnd < 0) throw const FormatException('Malformed part headers');

    final headerStr =
        String.fromCharCodes(data.sublist(pos, headerEnd));
    pos = headerEnd + 4;

    // Next boundary delimiter is \r\n--boundary
    final nextDelim =
        Uint8List.fromList([0x0D, 0x0A, ...dash2]);
    final bodyEnd = _indexOf(data, nextDelim, pos);
    if (bodyEnd < 0) throw const FormatException('No closing boundary');

    final partBytes = Uint8List.fromList(data.sublist(pos, bodyEnd));
    pos = bodyEnd + nextDelim.length;

    String? fieldName;
    String? filename;
    var partContentType = 'application/octet-stream';

    for (final line in headerStr.split('\r\n')) {
      final lower = line.toLowerCase();
      if (lower.startsWith('content-disposition:')) {
        for (final seg in line.split(';')) {
          final t = seg.trim();
          if (t.toLowerCase().startsWith('name=')) {
            fieldName = _unquote(t.substring(5));
          } else if (t.toLowerCase().startsWith('filename=')) {
            filename = _unquote(t.substring(9));
          }
        }
      } else if (lower.startsWith('content-type:')) {
        partContentType = line.substring('content-type:'.length).trim();
      }
    }

    if (filename != null && fieldName != null) {
      return UploadedFile(fieldName, filename, partContentType, partBytes);
    }
  }
  return null;
}

String? detectImageExt(Uint8List bytes) {
  if (bytes.length < 12) return null;
  // PNG: 89 50 4E 47 0D 0A 1A 0A
  if (bytes[0] == 0x89 &&
      bytes[1] == 0x50 &&
      bytes[2] == 0x4E &&
      bytes[3] == 0x47) return 'png';
  // JPEG: FF D8 FF
  if (bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF) return 'jpg';
  // WebP: RIFF????WEBP
  if (bytes[0] == 0x52 &&
      bytes[1] == 0x49 &&
      bytes[2] == 0x46 &&
      bytes[3] == 0x46 &&
      bytes[8] == 0x57 &&
      bytes[9] == 0x45 &&
      bytes[10] == 0x42 &&
      bytes[11] == 0x50) return 'webp';
  return null;
}

String _unquote(String s) {
  s = s.trim();
  if (s.length >= 2 && s.startsWith('"') && s.endsWith('"')) {
    return s.substring(1, s.length - 1);
  }
  return s;
}

int _indexOf(Uint8List haystack, Uint8List needle, int start) {
  if (needle.isEmpty) return start;
  outer:
  for (var i = start; i <= haystack.length - needle.length; i++) {
    for (var j = 0; j < needle.length; j++) {
      if (haystack[i + j] != needle[j]) continue outer;
    }
    return i;
  }
  return -1;
}
