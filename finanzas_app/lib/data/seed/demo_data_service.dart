import 'dart:math';

import 'package:uuid/uuid.dart';

import '../../core/money/money.dart';
import '../../core/utils/dates.dart';
import '../../core/utils/recurrence.dart';
import '../models/app_user.dart';
import '../models/category.dart';
import '../models/enums.dart';
import '../models/fin_transaction.dart';
import '../models/recurring_transaction.dart';
import '../repositories/budget_repository.dart';
import '../repositories/category_repository.dart';
import '../repositories/recurring_repository.dart';
import '../repositories/transaction_repository.dart';

/// Genera datos de prueba realistas: 6 meses de movimientos, presupuestos del
/// mes actual y 2 movimientos recurrentes. Es determinista (misma semilla).
class DemoDataService {
  DemoDataService({
    required CategoryRepository categories,
    required TransactionRepository transactions,
    required BudgetRepository budgets,
    required RecurringRepository recurring,
  })  : _categories = categories,
        _transactions = transactions,
        _budgets = budgets,
        _recurring = recurring;

  final CategoryRepository _categories;
  final TransactionRepository _transactions;
  final BudgetRepository _budgets;
  final RecurringRepository _recurring;
  static const _uuid = Uuid();

  Future<int> generate(AppUser user, {DateTime? today, int seed = 7}) async {
    await _categories.seedDefaults(user.id);
    final cats = await _categories.getAll(user.id);
    Category byIcon(String icon, TxType type) => cats.firstWhere(
          (c) => c.icon == icon && c.type == type,
          orElse: () => cats.firstWhere((c) => c.type == type),
        );

    final salary = byIcon('salary', TxType.income);
    final sales = byIcon('sales', TxType.income);
    final food = byIcon('food', TxType.expense);
    final home = byIcon('home', TxType.expense);
    final transport = byIcon('transport', TxType.expense);
    final services = byIcon('services', TxType.expense);
    final fun = byIcon('entertainment', TxType.expense);
    final health = byIcon('health', TxType.expense);
    final education = byIcon('education', TxType.expense);

    final rnd = Random(seed);
    final t = Dates.dateOnly(today ?? DateTime.now());
    final now = DateTime.now().toUtc();
    final txs = <FinTransaction>[];

    Money between(int minUnits, int maxUnits) =>
        Money(minUnits * 100 + rnd.nextInt((maxUnits - minUnits) * 100 + 1));

    void add(TxType type, Category c, Money amount, DateTime date, String desc, PaymentMethod method,
        {String? recurringId}) {
      if (date.isAfter(t)) return;
      txs.add(FinTransaction(
        id: _uuid.v4(),
        userId: user.id,
        type: type,
        amount: amount,
        categoryId: c.id,
        date: date,
        description: desc,
        paymentMethod: method,
        recurringId: recurringId,
        createdAt: now,
        updatedAt: now,
      ));
    }

    final firstMonth = DateTime(t.year, t.month - 5, 1);
    final salaryRule = RecurringTransaction(
      id: _uuid.v4(),
      userId: user.id,
      type: TxType.income,
      amount: Money.of(4500),
      categoryId: salary.id,
      description: 'Sueldo mensual',
      paymentMethod: PaymentMethod.transfer,
      frequency: Frequency.monthly,
      startDate: firstMonth,
      nextDate: Recurrence.next(DateTime(t.year, t.month, 1), Frequency.monthly),
      createdAt: now,
      updatedAt: now,
    );
    final rentStart = DateTime(firstMonth.year, firstMonth.month, 5);
    final rentThisMonth = DateTime(t.year, t.month, 5);
    final rentRule = RecurringTransaction(
      id: _uuid.v4(),
      userId: user.id,
      type: TxType.expense,
      amount: Money.of(1200),
      categoryId: home.id,
      description: 'Alquiler departamento',
      paymentMethod: PaymentMethod.transfer,
      frequency: Frequency.monthly,
      startDate: rentStart,
      nextDate: rentThisMonth.isAfter(t)
          ? rentThisMonth
          : Recurrence.next(rentThisMonth, Frequency.monthly, anchorDay: 5),
      createdAt: now,
      updatedAt: now,
    );
    await _recurring.insert(salaryRule);
    await _recurring.insert(rentRule);

    for (var m = 0; m < 6; m++) {
      final month = DateTime(firstMonth.year, firstMonth.month + m, 1);
      DateTime day(int d) => DateTime(month.year, month.month, min(d, Dates.daysInMonth(month.year, month.month)));

      add(TxType.income, salary, Money.of(4500), day(1), 'Sueldo mensual', PaymentMethod.transfer,
          recurringId: salaryRule.id);
      add(TxType.income, sales, between(150, 650), day(15), 'Venta de artículos', PaymentMethod.digitalWallet);
      add(TxType.expense, home, Money.of(1200), day(5), 'Alquiler departamento', PaymentMethod.transfer,
          recurringId: rentRule.id);
      add(TxType.expense, services, between(160, 230), day(10), 'Luz, agua e Internet', PaymentMethod.debitCard);
      add(TxType.expense, education, Money.of(300), day(12), 'Curso en línea', PaymentMethod.creditCard);
      for (final d in [3, 10, 17, 24]) {
        add(TxType.expense, food, between(60, 190), day(d), 'Supermercado', PaymentMethod.debitCard);
      }
      for (final d in [2, 9, 16, 23]) {
        add(TxType.expense, transport, between(15, 45), day(d), 'Movilidad', PaymentMethod.digitalWallet);
      }
      add(TxType.expense, fun, between(40, 140), day(20), 'Cine y cena', PaymentMethod.creditCard);
      if (m.isEven) {
        add(TxType.expense, health, between(80, 160), day(18), 'Consulta médica', PaymentMethod.cash);
      }
    }
    await _transactions.insertMany(txs);

    for (final entry in {food: 600, transport: 150, fun: 120}.entries) {
      final exists = await _budgets.findByCategoryMonth(user.id, entry.key.id, t.year, t.month);
      if (exists == null) {
        await _budgets.create(
          userId: user.id,
          categoryId: entry.key.id,
          limit: Money.of(entry.value),
          year: t.year,
          month: t.month,
        );
      }
    }
    return txs.length;
  }
}
