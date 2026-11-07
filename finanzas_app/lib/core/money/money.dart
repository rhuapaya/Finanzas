import 'package:flutter/foundation.dart';

import 'currency.dart';

/// Importe monetario exacto representado en centavos enteros.
///
/// Nunca usa `double` para cálculos: suma, resta y comparaciones son exactas.
/// `toDouble()` existe solo para dibujar gráficos.
@immutable
class Money implements Comparable<Money> {
  const Money(this.cents);

  /// Crea un importe a partir de unidades y centavos (p. ej. 12, 50 → 12.50).
  factory Money.of(int units, [int cents = 0]) {
    final sign = units < 0 ? -1 : 1;
    return Money(units * 100 + sign * cents);
  }

  final int cents;

  static const zero = Money(0);
  static const _maxIntegerDigits = 13;

  /// Convierte texto como "1234.5", "1234,50", "-12" o "1,234.56" en [Money].
  ///
  /// Lanza [FormatException] si el texto no es válido o tiene más de 2 decimales.
  static Money parse(String input) {
    var s = input.trim().replaceAll(' ', '').replaceAll(' ', '');
    if (s.isEmpty) throw const FormatException('El monto está vacío');

    var negative = false;
    if (s.startsWith('-')) {
      negative = true;
      s = s.substring(1);
    } else if (s.startsWith('+')) {
      s = s.substring(1);
    }

    final lastDot = s.lastIndexOf('.');
    final lastComma = s.lastIndexOf(',');
    String intPart;
    String fracPart;

    if (lastDot == -1 && lastComma == -1) {
      intPart = s;
      fracPart = '';
    } else {
      final sepIndex = lastDot > lastComma ? lastDot : lastComma;
      final sepChar = s[sepIndex];
      final hasBoth = lastDot != -1 && lastComma != -1;
      final occurrences = sepChar.allMatches(s).length;
      if (!hasBoth && occurrences > 1) {
        // "1.234.567" → separadores de miles.
        intPart = s.replaceAll(sepChar, '');
        fracPart = '';
      } else {
        intPart = s.substring(0, sepIndex).replaceAll(RegExp('[.,]'), '');
        fracPart = s.substring(sepIndex + 1);
      }
    }

    if (intPart.isEmpty && fracPart.isEmpty) {
      throw FormatException('Monto inválido: "$input"');
    }
    if (intPart.isNotEmpty && !RegExp(r'^\d+$').hasMatch(intPart)) {
      throw FormatException('Monto inválido: "$input"');
    }
    if (!RegExp(r'^\d{0,2}$').hasMatch(fracPart)) {
      throw FormatException('El monto admite como máximo 2 decimales: "$input"');
    }
    final normalizedInt = intPart.replaceFirst(RegExp(r'^0+(?=\d)'), '');
    if (normalizedInt.length > _maxIntegerDigits) {
      throw FormatException('El monto es demasiado grande: "$input"');
    }

    final units = int.parse(normalizedInt.isEmpty ? '0' : normalizedInt);
    final fraction = int.parse(fracPart.padRight(2, '0'));
    final cents = units * 100 + fraction;
    return Money(negative ? -cents : cents);
  }

  static Money? tryParse(String? input) {
    if (input == null) return null;
    try {
      return parse(input);
    } on FormatException {
      return null;
    }
  }

  /// Lee valores provenientes de JSON/BD remota (`"12.30"`, `12`, `12.3`).
  static Money fromDecimal(Object? value) {
    if (value == null) return zero;
    if (value is Money) return value;
    if (value is int) return Money(value * 100);
    if (value is double) return parse(value.toStringAsFixed(2));
    return parse(value.toString());
  }

  static Money sum(Iterable<Money> values) =>
      Money(values.fold<int>(0, (acc, m) => acc + m.cents));

  bool get isZero => cents == 0;
  bool get isNegative => cents < 0;
  bool get isPositive => cents > 0;

  Money abs() => Money(cents.abs());

  Money operator +(Money other) => Money(cents + other.cents);
  Money operator -(Money other) => Money(cents - other.cents);
  Money operator -() => Money(-cents);
  Money operator *(int factor) => Money(cents * factor);
  bool operator <(Money other) => cents < other.cents;
  bool operator <=(Money other) => cents <= other.cents;
  bool operator >(Money other) => cents > other.cents;
  bool operator >=(Money other) => cents >= other.cents;

  /// Porcentaje entero (truncado) que representa este importe sobre [total].
  int percentOf(Money total) {
    if (total.cents == 0) return 0;
    return (cents * 100) ~/ total.cents;
  }

  /// Proporción para barras de progreso y gráficos (solo visual).
  double ratioOf(Money total) {
    if (total.cents == 0) return 0;
    return cents / total.cents;
  }

  /// Solo para gráficos: no usar en cálculos.
  double toDouble() => cents / 100;

  /// Representación decimal canónica: "-1234.50".
  String toDecimalString() {
    final abs = cents.abs();
    final units = abs ~/ 100;
    final fraction = (abs % 100).toString().padLeft(2, '0');
    return '${cents < 0 ? '-' : ''}$units.$fraction';
  }

  /// Formatea según la moneda: "S/ 1,234.50", "1.234,50 €".
  String format(CurrencyInfo currency, {bool showPlusSign = false}) {
    final abs = cents.abs();
    final units = (abs ~/ 100).toString();
    final buffer = StringBuffer();
    for (var i = 0; i < units.length; i++) {
      if (i > 0 && (units.length - i) % 3 == 0) {
        buffer.write(currency.thousandSeparator);
      }
      buffer.write(units[i]);
    }
    final number =
        '$buffer${currency.decimalSeparator}${(abs % 100).toString().padLeft(2, '0')}';
    final sign = cents < 0 ? '-' : (showPlusSign && cents > 0 ? '+' : '');
    return currency.symbolFirst
        ? '$sign${currency.symbol} $number'
        : '$sign$number ${currency.symbol}';
  }

  @override
  int compareTo(Money other) => cents.compareTo(other.cents);

  @override
  bool operator ==(Object other) => other is Money && other.cents == cents;

  @override
  int get hashCode => cents.hashCode;

  @override
  String toString() => 'Money(${toDecimalString()})';
}
