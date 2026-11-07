import 'package:finanzas_app/core/money/currency.dart';
import 'package:finanzas_app/core/money/money.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Money.parse', () {
    test('acepta enteros y decimales con punto o coma', () {
      expect(Money.parse('12').cents, 1200);
      expect(Money.parse('12.5').cents, 1250);
      expect(Money.parse('12,50').cents, 1250);
      expect(Money.parse('0.01').cents, 1);
      expect(Money.parse('.5').cents, 50);
      expect(Money.parse('5.').cents, 500);
      expect(Money.parse('  1 234.56 ').cents, 123456);
    });

    test('interpreta separadores de miles', () {
      expect(Money.parse('1,234.56').cents, 123456);
      expect(Money.parse('1.234,56').cents, 123456);
      expect(Money.parse('1.234.567').cents, 123456700);
    });

    test('acepta signo', () {
      expect(Money.parse('-10.25').cents, -1025);
      expect(Money.parse('+3').cents, 300);
    });

    test('rechaza entradas inválidas', () {
      expect(() => Money.parse(''), throwsFormatException);
      expect(() => Money.parse('abc'), throwsFormatException);
      expect(() => Money.parse('1.234'), throwsFormatException, reason: 'más de 2 decimales');
      expect(() => Money.parse('12.3.4,5x'), throwsFormatException);
      expect(() => Money.parse('99999999999999'), throwsFormatException);
      expect(Money.tryParse('x'), isNull);
    });
  });

  group('aritmética exacta', () {
    test('0.1 + 0.2 == 0.3 (sin errores de punto flotante)', () {
      expect(Money.parse('0.1') + Money.parse('0.2'), Money.parse('0.3'));
    });

    test('suma, resta, negación y multiplicación', () {
      final a = Money.parse('100.10');
      final b = Money.parse('0.15');
      expect((a + b).cents, 10025);
      expect((a - b).cents, 9995);
      expect((-a).cents, -10010);
      expect((b * 3).cents, 45);
      expect(Money.sum([a, b, b]).cents, 10040);
    });

    test('comparaciones y porcentajes enteros', () {
      expect(Money.parse('80') < Money.parse('100'), isTrue);
      expect(Money.parse('80').percentOf(Money.parse('100')), 80);
      expect(Money.parse('79.99').percentOf(Money.parse('100')), 79);
      expect(Money.parse('10').percentOf(Money.zero), 0);
    });

    test('fromDecimal acepta texto, enteros y dobles', () {
      expect(Money.fromDecimal('45.10').cents, 4510);
      expect(Money.fromDecimal(45).cents, 4500);
      expect(Money.fromDecimal(45.1).cents, 4510);
      expect(Money.fromDecimal(null), Money.zero);
    });
  });

  group('formato', () {
    test('decimal canónico', () {
      expect(const Money(123456).toDecimalString(), '1234.56');
      expect(const Money(-5).toDecimalString(), '-0.05');
      expect(Money.zero.toDecimalString(), '0.00');
    });

    test('PEN por defecto', () {
      expect(const Money(123456789).format(CurrencyInfo.pen), 'S/ 1,234,567.89');
      expect(const Money(-1050).format(CurrencyInfo.pen), '-S/ 10.50');
      expect(const Money(1050).format(CurrencyInfo.pen, showPlusSign: true), '+S/ 10.50');
      expect(const Money(99).format(CurrencyInfo.pen), 'S/ 0.99');
    });

    test('EUR con símbolo al final y separadores europeos', () {
      expect(const Money(123456).format(CurrencyInfo.eur), '1.234,56 €');
    });

    test('byCode usa PEN si el código no existe', () {
      expect(CurrencyInfo.byCode('XXX').code, 'PEN');
      expect(CurrencyInfo.byCode('USD').code, 'USD');
    });
  });
}
