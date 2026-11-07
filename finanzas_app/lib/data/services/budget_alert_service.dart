import '../../core/finance/finance_calculator.dart';
import '../../core/money/currency.dart';
import '../../core/services/notification_service.dart';
import '../models/app_user.dart';
import '../repositories/budget_repository.dart';
import '../repositories/category_repository.dart';
import '../repositories/transaction_repository.dart';

/// Evalúa presupuestos y envía alertas al 80 % y 100 %.
class BudgetAlertService {
  BudgetAlertService({
    required BudgetRepository budgets,
    required TransactionRepository transactions,
    required CategoryRepository categories,
    required AlertNotifier notifier,
  })  : _budgets = budgets,
        _transactions = transactions,
        _categories = categories,
        _notifier = notifier;

  final BudgetRepository _budgets;
  final TransactionRepository _transactions;
  final CategoryRepository _categories;
  final AlertNotifier _notifier;

  /// Revisa el presupuesto de la categoría en el mes de [date].
  /// Devuelve los mensajes de alerta generados (para mostrarlos en pantalla).
  Future<List<String>> evaluate({
    required AppUser user,
    required String categoryId,
    required DateTime date,
  }) async {
    final budget = await _budgets.findByCategoryMonth(user.id, categoryId, date.year, date.month);
    if (budget == null) return const [];

    final spent = await _transactions.sumForCategoryMonth(user.id, categoryId, date.year, date.month);
    final decision = FinanceCalculator.evaluateBudgetAlert(
      limit: budget.limit,
      spent: spent,
      alert80Sent: budget.alert80Sent,
      alert100Sent: budget.alert100Sent,
    );

    if (decision.alert80Sent != budget.alert80Sent || decision.alert100Sent != budget.alert100Sent) {
      await _budgets.updateAlertFlags(
        budget.id,
        alert80Sent: decision.alert80Sent,
        alert100Sent: decision.alert100Sent,
      );
    }
    if (!decision.shouldNotify || !user.settings.budgetAlertsEnabled) return const [];

    final category = await _categories.getById(categoryId);
    final name = category?.name ?? 'la categoría';
    final currency = CurrencyInfo.byCode(user.settings.currency);
    final spentText = spent.format(currency);
    final limitText = budget.limit.format(currency);

    final String title;
    final String body;
    if (decision.notify100) {
      title = 'Presupuesto agotado: $name';
      body = 'Gastaste $spentText de $limitText (${spent.percentOf(budget.limit)} %).';
    } else {
      title = 'Presupuesto al 80 %: $name';
      body = 'Llevas $spentText de $limitText. Te quedan ${(budget.limit - spent).format(currency)}.';
    }

    if (user.settings.notificationsEnabled) {
      await _notifier.notify(id: budget.id.hashCode & 0x7fffffff, title: title, body: body);
    }
    return ['$title. $body'];
  }
}
