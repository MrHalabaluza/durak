import 'dart:math';
import 'dart:typed_data';
import 'package:hashlib/hashlib.dart';

class PasswordHasher {
  // moderate security: t=2, m=19MB, p=1 — meets minimum requirements
  static const _security = Argon2Security('prod', m: 19 * 1024, p: 1, t: 2);

  static String hash(String clientHashHex) {
    final salt = _randomBytes(16);
    final h = argon2id(
      Uint8List.fromList(clientHashHex.codeUnits),
      salt,
      security: _security,
    );
    return h.encoded();
  }

  static bool verify(String clientHashHex, String storedEncoded) {
    return argon2Verify(
      storedEncoded,
      Uint8List.fromList(clientHashHex.codeUnits),
    );
  }

  static Uint8List _randomBytes(int n) {
    final r = Random.secure();
    return Uint8List.fromList(List.generate(n, (_) => r.nextInt(256)));
  }
}
