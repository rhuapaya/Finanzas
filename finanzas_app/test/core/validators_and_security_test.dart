import 'package:finanzas_app/core/security/password_hasher.dart';
import 'package:finanzas_app/core/utils/validators.dart';
import 'package:flutter_test/flutter_test.dart';

String _hex(List<int> bytes) => bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

void main() {
  group('Validators', () {
    test('monto mayor que cero', () {
      expect(Validators.amount(''), isNotNull);
      expect(Validators.amount('0'), 'El monto debe ser mayor que cero');
      expect(Validators.amount('0.00'), isNotNull);
      expect(Validators.amount('-5'), isNotNull);
      expect(Validators.amount('1.234'), isNotNull);
      expect(Validators.amount('abc'), isNotNull);
      expect(Validators.amount('0.01'), isNull);
      expect(Validators.amount('150,50'), isNull);
    });

    test('correo', () {
      expect(Validators.email('ana@correo.pe'), isNull);
      expect(Validators.email('ana.perez+fin@empresa.com.pe'), isNull);
      expect(Validators.email('ana@'), isNotNull);
      expect(Validators.email(''), isNotNull);
    });

    test('contraseña segura', () {
      expect(Validators.password('abc'), isNotNull);
      expect(Validators.password('abcdefgh'), isNotNull);
      expect(Validators.password('12345678'), isNotNull);
      expect(Validators.password('clave2026'), isNull);
    });

    test('nombre de categoría', () {
      expect(Validators.categoryName('  '), isNotNull);
      expect(Validators.categoryName('x' * 41), isNotNull);
      expect(Validators.categoryName('Mascotas'), isNull);
    });
  });

  group('PasswordHasher', () {
    test('PBKDF2-HMAC-SHA256 coincide con vectores conocidos', () {
      expect(_hex(PasswordHasher.pbkdf2('password'.codeUnits, 'salt'.codeUnits, 1, 32)),
          '120fb6cffcf8b32c43e7225256c4f837a86548c92ccc35480805987cb70be17b');
      expect(_hex(PasswordHasher.pbkdf2('password'.codeUnits, 'salt'.codeUnits, 2, 32)),
          'ae4d0c95af6b46d32d0adff928f06dd02a303f8ef3c251dfd6e2d85a95474c43');
    });

    test('hash y verificación', () {
      final salt = PasswordHasher.generateSalt();
      final hash = PasswordHasher.hash('clave2026', salt, iterations: 1000);
      expect(PasswordHasher.verify('clave2026', salt, hash, iterations: 1000), isTrue);
      expect(PasswordHasher.verify('otra2026', salt, hash, iterations: 1000), isFalse);
    });

    test('código de recuperación legible y normalizable', () {
      final code = PasswordHasher.generateRecoveryCode();
      expect(RegExp(r'^[A-Z2-9]{4}-[A-Z2-9]{4}$').hasMatch(code), isTrue);
      expect(PasswordHasher.normalizeRecoveryCode('ab12-cd34'), 'AB12CD34');
    });
  });
}
