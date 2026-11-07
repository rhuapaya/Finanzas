import 'package:flutter/material.dart';

import '../../data/models/enums.dart';

abstract final class AppTheme {
  static const seed = Color(0xFF00796B);

  static ThemeData light() => _build(ColorScheme.fromSeed(seedColor: seed));

  static ThemeData dark() =>
      _build(ColorScheme.fromSeed(seedColor: seed, brightness: Brightness.dark));

  static ThemeData _build(ColorScheme scheme) {
    final radius = BorderRadius.circular(14);
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.surface,
      visualDensity: VisualDensity.standard,
      materialTapTargetSize: MaterialTapTargetSize.padded,
      appBarTheme: AppBarTheme(
        centerTitle: false,
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 1,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerHighest.withAlpha(110),
        border: OutlineInputBorder(borderRadius: radius),
        enabledBorder: OutlineInputBorder(
          borderRadius: radius,
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(64, 52),
          shape: RoundedRectangleBorder(borderRadius: radius),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(64, 52),
          shape: RoundedRectangleBorder(borderRadius: radius),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
      ),
      chipTheme: ChipThemeData(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20))),
      listTileTheme: const ListTileThemeData(minVerticalPadding: 10),
      snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
      navigationBarTheme: NavigationBarThemeData(
        height: 72,
        indicatorColor: scheme.primaryContainer,
        labelTextStyle: WidgetStateProperty.all(const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
      ),
    );
  }
}

/// Colores semánticos con contraste suficiente (WCAG AA) en ambos temas.
extension FinanceColors on ColorScheme {
  Color get income =>
      brightness == Brightness.light ? const Color(0xFF1B6E34) : const Color(0xFF7FD99A);

  Color get expense =>
      brightness == Brightness.light ? const Color(0xFFB3261E) : const Color(0xFFFFB4AB);

  Color get warning =>
      brightness == Brightness.light ? const Color(0xFF8A5300) : const Color(0xFFFFB95C);

  Color forType(TxType type) => type == TxType.income ? income : expense;
}
