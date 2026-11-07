import 'package:flutter/foundation.dart';

import '../../data/models/enums.dart';
import '../../data/models/fin_transaction.dart';
import '../money/money.dart';
import '../utils/date_range.dart';

@immutable
class PeriodSummary {
  const PeriodSummary({required this.income, required this.expense, this.count = 0});

  static const empty = PeriodSummary(income: Money.zero, expense: Money.zero);

  final Money income;
  final Money expense;
  final int count;

  /// Ingresos menos egresos.
  Money get balance => income - expense;

  /// Porcentaje de ahorro sobre ingresos (entero, puede ser negativo).
  int get savingsRate => income.isZero ? 0 : balance.percentOf(income);
}

@immutable
class CategoryTotal {
  const CategoryTotal({required this.categoryId, required this.total, required this.percent, this.count = 0});

  final String categoryId;
  final Money total;

  /// Participación sobre el total del tipo (0–100, entero).
  final int percent;
  final int count;
}

@immutable
class MonthlyTotal {
  const MonthlyTotal({required this.year, required this.month, required this.income, required this.expense});

  final int year;
  final int month;
  final Money income;
  final Money expense;

  Money get net => income - expense;
}

enum BudgetLevel { ok, warning, exceeded }

@immutable
class BudgetStatus {
  const BudgetStatus({required this.limit, required this.spent});

  final Money limit;
  final Money spent;

  /// Disponible (negativo si se excedió).
  Money get available => limit - spent;
  int get percent => spent.percentOf(limit);
  double get progress => spent.ratioOf(limit).clamp(0.0, 1.0).toDouble();
  BudgetLevel get level => FinanceCalculator.levelFor(limit: limit, spent: spent);
}

/// Resultado de evaluar si corresponde enviar alertas de presupuesto.
@immutable
class BudgetAlertDecision {
  const BudgetAlertDecision({
    required this.notify80,
    required this.notify100,
    required this.alert80Sent,
    required this.alert100Sent,
  });

  final bool notify80;
  final bool notify100;

  /// Nuevos valores de las marcas persistidas.
  final bool alert80Sent;
  final bool alert100Sent;

  bool get shouldNotify => notify80 || notify100;
}

/// Cálculos financieros puros (sin E/S), cubiertos por pruebas unitarias.
abstract final class FinanceCalculator {
  static const warningThreshold = 80;
  static const limitThreshold = 100;

  static PeriodSummary summarize(Iterable<FinTransaction> txs, {DateRange? range}) {
    var income = 0;
    var expense = 0;
    var count = 0;
    for (final t in txs) {
      if (t.deletedAt != null) continue;
      if (range != null && !range.contains(t.date)) continue;
      count++;
      if (t.type == TxType.income) {
        income += t.amount.cents;
      } else {
        expense += t.amount.cents;
      }
    }
    return PeriodSummary(income: Money(income), expense: Money(expense), count: count);
  }

  /// Saldo = ingresos − egresos (opcionalmente hasta [upTo] inclusive).
  static Money balance(Iterable<FinTransaction> txs, {DateTime? upTo}) {
    var cents = 0;
    for (final t in txs) {
      if (t.deletedAt != null) continue;
      if (upTo != null && t.date.isAfter(upTo)) continue;
      cents += t.signedAmount.cents;
    }
    return Money(cents);
  }

  /// Totales por categoría para un tipo, ordenados de mayor a menor.
  static List<CategoryTotal> totalsByCategory(Iterable<FinTransaction> txs, TxType type) {
    final totals = <String, int>{};
    final counts = <String, int>{};
    var grand = 0;
    for (final t in txs) {
      if (t.deletedAt != null || t.type != type) continue;
      totals[t.categoryId] = (totals[t.categoryId] ?? 0) + t.amount.cents;
      counts[t.categoryId] = (counts[t.categoryId] ?? 0) + 1;
      grand += t.amount.cents;
    }
    final result = totals.entries
        .map((e) => CategoryTotal(
              categoryId: e.key,
              total: Money(e.value),
              percent: grand == 0 ? 0 : (e.value * 100 / grand).round(),
              count: counts[e.key] ?? 0,
            ))
        .toList()
      ..sort((a, b) => b.total.compareTo(a.total));
    return result;
  }

  /// Totales mensuales de los últimos [months] meses que terminan en [endMonth].
  static List<MonthlyTotal> monthlyTotals(
    Iterable<FinTransaction> txs, {
    required DateTime endMonth,
    int months = 6,
  }) {
    final keys = <int>[];
    for (var i = months - 1; i >= 0; i--) {
      final d = DateTime(endMonth.year, endMonth.month - i, 1);
      keys.add(d.year * 100 + d.month);
    }
    final income = {for (final k in keys) k: 0};
    final expense = {for (final k in keys) k: 0};
    for (final t in txs) {
      if (t.deletedAt != null) continue;
      final k = t.date.year * 100 + t.date.month;
      if (!income.containsKey(k)) continue;
      if (t.type == TxType.income) {
        income[k] = income[k]! + t.amount.cents;
      } else {
        expense[k] = expense[k]! + t.amount.cents;
      }
    }
    return keys
        .map((k) => MonthlyTotal(
              year: k ~/ 100,
              month: k % 100,
              income: Money(income[k]!),
              expense: Money(expense[k]!),
            ))
        .toList();
  }

  /// Variación porcentual entre dos importes (null si el anterior es cero).
  static int? percentChange(Money previous, Money current) {
    if (previous.isZero) return null;
    return ((current.cents - previous.cents) * 100 / previous.cents.abs()).round();
  }

  /// Nivel del presupuesto usando aritmética entera (sin redondeos).
  static BudgetLevel levelFor({required Money limit, required Money spent}) {
    if (limit.cents <= 0) return BudgetLevel.ok;
    if (spent.cents * 100 >= limit.cents * limitThreshold) return BudgetLevel.exceeded;
    if (spent.cents * 100 >= limit.cents * warningThreshold) return BudgetLevel.warning;
    return BudgetLevel.ok;
  }

  /// Decide qué alertas enviar y actualiza las marcas.
  ///
  /// - Al cruzar 80 % se avisa una sola vez; al cruzar 100 % también.
  /// - Si el gasto vuelve a bajar del umbral (edición/eliminación) la marca se
  ///   reinicia para poder volver a avisar.
  static BudgetAlertDecision evaluateBudgetAlert({
    required Money limit,
    required Money spent,
    required bool alert80Sent,
    required bool alert100Sent,
  }) {
    final level = levelFor(limit: limit, spent: spent);
    final reached80 = level != BudgetLevel.ok;
    final reached100 = level == BudgetLevel.exceeded;

    final notify100 = reached100 && !alert100Sent;
    // Si se salta directamente al 100 %, solo se envía la alerta de 100 %.
    final notify80 = reached80 && !alert80Sent && !notify100;

    return BudgetAlertDecision(
      notify80: notify80,
      notify100: notify100,
      alert80Sent: reached80,
      alert100Sent: reached100,
    );
  }
}
