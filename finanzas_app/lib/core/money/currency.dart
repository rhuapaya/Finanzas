/// Información de formato de una moneda. Todas usan 2 decimales.
class CurrencyInfo {
  const CurrencyInfo({
    required this.code,
    required this.name,
    required this.symbol,
    this.symbolFirst = true,
    this.thousandSeparator = ',',
    this.decimalSeparator = '.',
  });

  final String code;
  final String name;
  final String symbol;
  final bool symbolFirst;
  final String thousandSeparator;
  final String decimalSeparator;

  static const pen = CurrencyInfo(code: 'PEN', name: 'Sol peruano', symbol: 'S/');
  static const usd = CurrencyInfo(code: 'USD', name: 'Dólar estadounidense', symbol: r'US$');
  static const eur = CurrencyInfo(
    code: 'EUR',
    name: 'Euro',
    symbol: '€',
    symbolFirst: false,
    thousandSeparator: '.',
    decimalSeparator: ',',
  );
  static const mxn = CurrencyInfo(code: 'MXN', name: 'Peso mexicano', symbol: r'MX$');
  static const cop = CurrencyInfo(
    code: 'COP',
    name: 'Peso colombiano',
    symbol: r'COL$',
    thousandSeparator: '.',
    decimalSeparator: ',',
  );
  static const ars = CurrencyInfo(
    code: 'ARS',
    name: 'Peso argentino',
    symbol: r'AR$',
    thousandSeparator: '.',
    decimalSeparator: ',',
  );
  static const brl = CurrencyInfo(
    code: 'BRL',
    name: 'Real brasileño',
    symbol: r'R$',
    thousandSeparator: '.',
    decimalSeparator: ',',
  );
  static const gbp = CurrencyInfo(code: 'GBP', name: 'Libra esterlina', symbol: '£');

  static const List<CurrencyInfo> all = [pen, usd, eur, mxn, cop, ars, brl, gbp];

  static CurrencyInfo byCode(String? code) =>
      all.firstWhere((c) => c.code == code, orElse: () => pen);
}
