import 'package:flutter/material.dart';

enum TxType {
  income('income', 'Ingreso', 'Ingresos'),
  expense('expense', 'Egreso', 'Egresos');

  const TxType(this.code, this.label, this.pluralLabel);
  final String code;
  final String label;
  final String pluralLabel;

  static TxType fromCode(String? code) =>
      TxType.values.firstWhere((t) => t.code == code, orElse: () => TxType.expense);
}

enum PaymentMethod {
  cash('cash', 'Efectivo', Icons.payments_outlined),
  debitCard('debit_card', 'Tarjeta de débito', Icons.credit_card),
  creditCard('credit_card', 'Tarjeta de crédito', Icons.credit_score),
  transfer('transfer', 'Transferencia', Icons.account_balance),
  digitalWallet('digital_wallet', 'Billetera digital (Yape/Plin)', Icons.qr_code_2),
  other('other', 'Otro', Icons.more_horiz);

  const PaymentMethod(this.code, this.label, this.icon);
  final String code;
  final String label;
  final IconData icon;

  static PaymentMethod fromCode(String? code) =>
      PaymentMethod.values.firstWhere((p) => p.code == code, orElse: () => PaymentMethod.other);
}

enum Frequency {
  daily('daily', 'Diario'),
  weekly('weekly', 'Semanal'),
  biweekly('biweekly', 'Quincenal'),
  monthly('monthly', 'Mensual'),
  yearly('yearly', 'Anual');

  const Frequency(this.code, this.label);
  final String code;
  final String label;

  static Frequency fromCode(String? code) =>
      Frequency.values.firstWhere((f) => f.code == code, orElse: () => Frequency.monthly);
}

enum RecurringStatus {
  active('active', 'Activo'),
  paused('paused', 'Pausado'),
  finished('finished', 'Finalizado');

  const RecurringStatus(this.code, this.label);
  final String code;
  final String label;

  static RecurringStatus fromCode(String? code) =>
      RecurringStatus.values.firstWhere((s) => s.code == code, orElse: () => RecurringStatus.active);
}

enum AppThemeMode {
  light('light', 'Claro'),
  dark('dark', 'Oscuro'),
  system('system', 'Automático');

  const AppThemeMode(this.code, this.label);
  final String code;
  final String label;

  ThemeMode get flutterMode => switch (this) {
        AppThemeMode.light => ThemeMode.light,
        AppThemeMode.dark => ThemeMode.dark,
        AppThemeMode.system => ThemeMode.system,
      };

  static AppThemeMode fromCode(String? code) =>
      AppThemeMode.values.firstWhere((m) => m.code == code, orElse: () => AppThemeMode.system);
}

/// Estado de sincronización de una fila local.
abstract final class SyncStatus {
  static const pending = 'pending';
  static const synced = 'synced';
}
