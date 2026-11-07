import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/money/money.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models/enums.dart';
import '../../providers.dart';

/// Importe formateado con la moneda del usuario.
class AmountText extends ConsumerWidget {
  const AmountText(
    this.amount, {
    super.key,
    this.type,
    this.style,
    this.colored = true,
    this.showSign = false,
  });

  final Money amount;

  /// Si se indica, colorea y antepone el signo según ingreso/egreso.
  final TxType? type;
  final TextStyle? style;
  final bool colored;
  final bool showSign;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currency = ref.watch(currencyProvider);
    final scheme = Theme.of(context).colorScheme;
    final value = switch (type) {
      TxType.income => amount.abs(),
      TxType.expense => -amount.abs(),
      null => amount,
    };
    final text = value.format(currency, showPlusSign: showSign || type == TxType.income);
    Color? color;
    if (colored) {
      if (type != null) {
        color = scheme.forType(type!);
      } else if (amount.isNegative) {
        color = scheme.expense;
      }
    }
    return Text(
      text,
      style: (style ?? Theme.of(context).textTheme.bodyLarge)?.copyWith(
        color: color,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}

/// Permite solo números con hasta 2 decimales; convierte la coma en punto.
class AmountInputFormatter extends TextInputFormatter {
  static final _pattern = RegExp(r'^\d{0,12}(\.\d{0,2})?$');

  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final text = newValue.text.replaceAll(',', '.');
    if (text.isEmpty) return newValue;
    if (!_pattern.hasMatch(text)) return oldValue;
    return newValue.copyWith(text: text);
  }
}

/// Campo de monto con teclado numérico.
class AmountField extends ConsumerWidget {
  const AmountField({
    super.key,
    required this.controller,
    this.label = 'Monto',
    this.validator,
    this.autofocus = false,
    this.fieldKey,
  });

  final TextEditingController controller;
  final String label;
  final FormFieldValidator<String>? validator;
  final bool autofocus;
  final Key? fieldKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currency = ref.watch(currencyProvider);
    return TextFormField(
      key: fieldKey,
      controller: controller,
      autofocus: autofocus,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      textInputAction: TextInputAction.next,
      inputFormatters: [AmountInputFormatter()],
      style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w600),
      decoration: InputDecoration(
        labelText: label,
        hintText: '0.00',
        prefixText: currency.symbolFirst ? '${currency.symbol} ' : null,
        suffixText: currency.symbolFirst ? null : ' ${currency.symbol}',
      ),
      validator: validator,
    );
  }
}
