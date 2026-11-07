import 'package:uuid/uuid.dart';

import '../../core/errors/app_exception.dart';
import '../../core/money/money.dart';
import '../../core/services/notification_service.dart';
import '../../core/utils/dates.dart';
import '../../core/utils/recurrence.dart';
import '../models/app_user.dart';
import '../models/enums.dart';
import '../models/recurring_transaction.dart';
import '../repositories/recurring_repository.dart';
import 'transaction_service.dart';

class RecurringDraft {
  const RecurringDraft({
    required this.type,
    required this.amount,
    required this.categoryId,
    required this.frequency,
    required this.startDate,
    this.endDate,
    this.description,
    this.paymentMethod = PaymentMethod.cash,
  });

  final TxType type;
  final Money amount;
  final String categoryId;
  final Frequency frequency;
  final DateTime startDate;
  final DateTime? endDate;
  final String? description;
  final PaymentMethod paymentMethod;
}

/// Gestiona reglas recurrentes y genera los movimientos vencidos.
class RecurringService {
  RecurringService(this._repo, this._transactions, this._notifier);

  final RecurringRepository _repo;
  final TransactionService _transactions;
  final AlertNotifier _notifier;
  static const _uuid = Uuid();

  static void validate(RecurringDraft d) {
    if (!d.amount.isPositive) throw const ValidationException('El monto debe ser mayor que cero.');
    if (d.categoryId.isEmpty) throw const ValidationException('Selecciona una categoría.');
    if (d.endDate != null && Dates.dateOnly(d.endDate!).isBefore(Dates.dateOnly(d.startDate))) {
      throw const ValidationException('La fecha de fin no puede ser anterior al inicio.');
    }
  }

  /// Crea la regla. La primera ocurrencia es [RecurringDraft.startDate];
  /// todas las vencidas hasta hoy se registran de inmediato. Si se indica
  /// [firstReceiptPath], el comprobante se adjunta al primer movimiento.
  Future<(RecurringTransaction, List<String>)> create(
    AppUser user,
    RecurringDraft d, {
    DateTime? today,
    String? firstReceiptPath,
  }) async {
    validate(d);
    final t = Dates.dateOnly(today ?? Dates.today());
    final now = DateTime.now().toUtc();
    var rule = RecurringTransaction(
      id: _uuid.v4(),
      userId: user.id,
      type: d.type,
      amount: d.amount,
      categoryId: d.categoryId,
      description: d.description?.trim().isEmpty ?? true ? null : d.description!.trim(),
      paymentMethod: d.paymentMethod,
      frequency: d.frequency,
      startDate: Dates.dateOnly(d.startDate),
      nextDate: Dates.dateOnly(d.startDate),
      endDate: d.endDate == null ? null : Dates.dateOnly(d.endDate!),
      createdAt: now,
      updatedAt: now,
    );
    final alerts = <String>[];
    if (firstReceiptPath != null && !rule.startDate.isAfter(t)) {
      final first = await _transactions.create(
        user,
        TransactionDraft(
          type: rule.type,
          amount: rule.amount,
          categoryId: rule.categoryId,
          date: rule.startDate,
          description: rule.description,
          paymentMethod: rule.paymentMethod,
          receiptLocalPath: firstReceiptPath,
          recurringId: rule.id,
        ),
      );
      alerts.addAll(first.alerts);
      rule = rule.copyWith(
        nextDate: Recurrence.next(rule.startDate, rule.frequency, anchorDay: rule.anchorDay),
        lastGeneratedAt: now,
      );
    }
    await _repo.insert(rule);
    final (_, more) = await _process(user, rule, t);
    alerts.addAll(more);
    return ((await _repo.getById(rule.id)) ?? rule, alerts);
  }

  Future<RecurringTransaction> update(RecurringTransaction rule) async {
    validate(RecurringDraft(
      type: rule.type,
      amount: rule.amount,
      categoryId: rule.categoryId,
      frequency: rule.frequency,
      startDate: rule.startDate,
      endDate: rule.endDate,
    ));
    return _repo.update(rule);
  }

  Future<RecurringTransaction> setStatus(RecurringTransaction rule, RecurringStatus status) =>
      _repo.update(rule.copyWith(status: status));

  Future<void> delete(String id) => _repo.softDelete(id);

  /// Genera todos los movimientos vencidos de las reglas activas.
  /// Devuelve la cantidad de movimientos creados y las alertas de presupuesto.
  Future<(int, List<String>)> processDue(AppUser user, {DateTime? today}) async {
    final t = today ?? Dates.today();
    final rules = await _repo.due(user.id, t);
    var created = 0;
    final alerts = <String>[];
    for (final rule in rules) {
      final (count, ruleAlerts) = await _process(user, rule, t);
      created += count;
      alerts.addAll(ruleAlerts);
    }
    if (created > 0 && user.settings.notificationsEnabled && user.settings.recurringRemindersEnabled) {
      await _notifier.notify(
        id: 900001,
        title: 'Movimientos recurrentes registrados',
        body: created == 1
            ? 'Se registró 1 movimiento recurrente.'
            : 'Se registraron $created movimientos recurrentes.',
      );
    }
    return (created, alerts);
  }

  Future<(int, List<String>)> _process(AppUser user, RecurringTransaction rule, DateTime today) async {
    if (rule.status != RecurringStatus.active) return (0, const <String>[]);
    final due = Recurrence.due(
      nextDate: rule.nextDate,
      today: today,
      frequency: rule.frequency,
      anchorDay: rule.anchorDay,
      endDate: rule.endDate,
    );
    final alerts = <String>[];
    for (final date in due.dates) {
      final result = await _transactions.create(
        user,
        TransactionDraft(
          type: rule.type,
          amount: rule.amount,
          categoryId: rule.categoryId,
          date: date,
          description: rule.description,
          paymentMethod: rule.paymentMethod,
          recurringId: rule.id,
        ),
      );
      alerts.addAll(result.alerts);
    }
    final finished = due.finished;
    if (due.dates.isNotEmpty || finished) {
      await _repo.update(rule.copyWith(
        nextDate: due.nextDate,
        status: finished ? RecurringStatus.finished : rule.status,
        lastGeneratedAt: due.dates.isNotEmpty ? DateTime.now().toUtc() : rule.lastGeneratedAt,
      ));
    }
    return (due.dates.length, alerts);
  }
}
