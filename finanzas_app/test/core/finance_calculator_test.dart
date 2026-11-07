import 'package:finanzas_app/core/finance/finance_calculator.dart';
import 'package:finanzas_app/core/money/money.dart';
import 'package:finanzas_app/core/utils/date_range.dart';
import 'package:finanzas_app/data/models/enums.dart';
import 'package:finanzas_app/data/models/fin_transaction.dart';
import 'package:flutter_test/flutter_test.dart';

FinTransaction tx(
  TxType type,
  String amount,
  DateTime date, {
  String category = 'c1',
  bool deleted = false,
}) {
  final now = DateTime.utc(2026, 1, 1);
  return FinTransaction(
    id: '${type.code}-$amount-${date.toIso8601String()}-$category',
    userId: 'u1',
    type: type,
    amount: Money.parse(amount),
    categoryId: category,
    date: date,
    createdAt: now,
    updatedAt: now,
    deletedAt: deleted ? now : null,
  );
}

void main() {
  final txs = [
    tx(TxType.income, '4500.00', DateTime(2026, 10, 1), category: 'salary'),
    tx(TxType.expense, '1200.00', DateTime(2026, 10, 5), category: 'home'),
    tx(TxType.expense, '300.50', DateTime(2026, 10, 10), category: 'food'),
    tx(TxType.expense, '99.50', DateTime(2026, 10, 20), category: 'food'),
    tx(TxType.income, '500.00', DateTime(2026, 11, 2), category: 'sales'),
    tx(TxType.expense, '50.00', DateTime(2026, 11, 3), category: 'food'),
    tx(TxType.expense, '999.99', DateTime(2026, 11, 3), category: 'food', deleted: true),
  ];

  group('summarize', () {
    test('suma ingresos y egresos e ignora eliminados', () {
      final s = FinanceCalculator.summarize(txs);
      expect(s.income, Money.parse('5000.00'));
      expect(s.expense, Money.parse('1650.00'));
      expect(s.balance, Money.parse('3350.00'));
      expect(s.count, 6);
    });

    test('filtra por rango', () {
      final october = DateRange.forPeriod(PeriodType.month, DateTime(2026, 10, 15));
      final s = FinanceCalculator.summarize(txs, range: october);
      expect(s.income, Money.parse('4500'));
      expect(s.expense, Money.parse('1600'));
      expect(s.balance, Money.parse('2900'));
      expect(s.savingsRate, 64);
    });

    test('vacío', () {
      final s = FinanceCalculator.summarize(const []);
      expect(s.balance, Money.zero);
      expect(s.savingsRate, 0);
    });
  });

  test('balance hasta una fecha', () {
    expect(FinanceCalculator.balance(txs), Money.parse('3350'));
    expect(FinanceCalculator.balance(txs, upTo: DateTime(2026, 10, 31)), Money.parse('2900'));
  });

  test('totalsByCategory ordena de mayor a menor y calcula porcentajes', () {
    final totals = FinanceCalculator.totalsByCategory(txs, TxType.expense);
    expect(totals.map((t) => t.categoryId), ['home', 'food']);
    expect(totals[0].total, Money.parse('1200'));
    expect(totals[1].total, Money.parse('450'));
    expect(totals[1].count, 3);
    expect(totals[0].percent + totals[1].percent, 100);
    expect(totals[0].percent, 73);
  });

  test('monthlyTotals genera todos los meses, incluso vacíos', () {
    final months = FinanceCalculator.monthlyTotals(txs, endMonth: DateTime(2026, 11), months: 3);
    expect(months.length, 3);
    expect(months.map((m) => m.month), [9, 10, 11]);
    expect(months[0].income, Money.zero);
    expect(months[1].net, Money.parse('2900'));
    expect(months[2].income, Money.parse('500'));
    expect(months[2].expense, Money.parse('50'));
  });

  test('monthlyTotals cruza el cambio de año', () {
    final list = [tx(TxType.expense, '10', DateTime(2025, 12, 31)), tx(TxType.expense, '20', DateTime(2026, 1, 1))];
    final months = FinanceCalculator.monthlyTotals(list, endMonth: DateTime(2026, 1), months: 2);
    expect(months.map((m) => '${m.year}-${m.month}'), ['2025-12', '2026-1']);
    expect(months[0].expense, Money.parse('10'));
    expect(months[1].expense, Money.parse('20'));
  });

  test('percentChange', () {
    expect(FinanceCalculator.percentChange(Money.parse('100'), Money.parse('150')), 50);
    expect(FinanceCalculator.percentChange(Money.parse('200'), Money.parse('150')), -25);
    expect(FinanceCalculator.percentChange(Money.zero, Money.parse('10')), isNull);
  });

  group('presupuestos', () {
    final limit = Money.parse('500');

    test('niveles con aritmética entera', () {
      expect(FinanceCalculator.levelFor(limit: limit, spent: Money.parse('399.99')), BudgetLevel.ok);
      expect(FinanceCalculator.levelFor(limit: limit, spent: Money.parse('400')), BudgetLevel.warning);
      expect(FinanceCalculator.levelFor(limit: limit, spent: Money.parse('499.99')), BudgetLevel.warning);
      expect(FinanceCalculator.levelFor(limit: limit, spent: Money.parse('500')), BudgetLevel.exceeded);
      expect(FinanceCalculator.levelFor(limit: limit, spent: Money.parse('800')), BudgetLevel.exceeded);
    });

    test('BudgetStatus calcula consumido, disponible y progreso', () {
      final s = BudgetStatus(limit: limit, spent: Money.parse('620'));
      expect(s.available, Money.parse('-120'));
      expect(s.percent, 124);
      expect(s.progress, 1.0);
      final ok = BudgetStatus(limit: limit, spent: Money.parse('125'));
      expect(ok.available, Money.parse('375'));
      expect(ok.progress, closeTo(0.25, 1e-9));
    });

    test('alerta al 80 % una sola vez', () {
      final first = FinanceCalculator.evaluateBudgetAlert(
          limit: limit, spent: Money.parse('410'), alert80Sent: false, alert100Sent: false);
      expect(first.notify80, isTrue);
      expect(first.notify100, isFalse);
      expect(first.alert80Sent, isTrue);

      final again = FinanceCalculator.evaluateBudgetAlert(
          limit: limit, spent: Money.parse('450'), alert80Sent: true, alert100Sent: false);
      expect(again.shouldNotify, isFalse);
    });

    test('alerta al 100 % y salto directo solo envía la de 100 %', () {
      final reach = FinanceCalculator.evaluateBudgetAlert(
          limit: limit, spent: Money.parse('500'), alert80Sent: true, alert100Sent: false);
      expect(reach.notify100, isTrue);
      expect(reach.notify80, isFalse);

      final jump = FinanceCalculator.evaluateBudgetAlert(
          limit: limit, spent: Money.parse('900'), alert80Sent: false, alert100Sent: false);
      expect(jump.notify100, isTrue);
      expect(jump.notify80, isFalse);
      expect(jump.alert80Sent, isTrue);
      expect(jump.alert100Sent, isTrue);
    });

    test('si el gasto baja, las marcas se reinician', () {
      final d = FinanceCalculator.evaluateBudgetAlert(
          limit: limit, spent: Money.parse('100'), alert80Sent: true, alert100Sent: true);
      expect(d.shouldNotify, isFalse);
      expect(d.alert80Sent, isFalse);
      expect(d.alert100Sent, isFalse);
    });
  });
}
