import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

/// PBKDF2-HMAC-SHA256 para contraseñas de cuentas locales.
abstract final class PasswordHasher {
  static const defaultIterations = 10000;
  static const keyLength = 32;

  static String generateSalt([int length = 16]) {
    final rnd = Random.secure();
    final bytes = List<int>.generate(length, (_) => rnd.nextInt(256));
    return base64UrlEncode(bytes);
  }

  /// Código de recuperación legible (sin caracteres ambiguos), p. ej. "K7PM-Q2XA".
  static String generateRecoveryCode() {
    const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final rnd = Random.secure();
    String block() => List.generate(4, (_) => alphabet[rnd.nextInt(alphabet.length)]).join();
    return '${block()}-${block()}';
  }

  static String normalizeRecoveryCode(String code) =>
      code.toUpperCase().replaceAll(RegExp('[^A-Z0-9]'), '');

  static List<int> pbkdf2(List<int> password, List<int> salt, int iterations, int length) {
    final hmac = Hmac(sha256, password);
    final blocks = (length / 32).ceil();
    final output = <int>[];
    for (var i = 1; i <= blocks; i++) {
      final blockInput = <int>[...salt, (i >> 24) & 0xff, (i >> 16) & 0xff, (i >> 8) & 0xff, i & 0xff];
      var u = hmac.convert(blockInput).bytes;
      final t = List<int>.from(u);
      for (var j = 1; j < iterations; j++) {
        u = hmac.convert(u).bytes;
        for (var k = 0; k < t.length; k++) {
          t[k] ^= u[k];
        }
      }
      output.addAll(t);
    }
    return output.sublist(0, length);
  }

  static String hash(String password, String salt, {int iterations = defaultIterations}) {
    final key = pbkdf2(utf8.encode(password), utf8.encode(salt), iterations, keyLength);
    return base64UrlEncode(key);
  }

  static bool verify(String password, String salt, String expectedHash,
      {int iterations = defaultIterations}) {
    final actual = hash(password, salt, iterations: iterations);
    return constantTimeEquals(actual, expectedHash);
  }

  static bool constantTimeEquals(String a, String b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return diff == 0;
  }
}
