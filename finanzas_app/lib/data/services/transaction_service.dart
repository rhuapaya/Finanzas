import 'dart:io';

import 'package:uuid/uuid.dart';

import '../../core/errors/app_exception.dart';
import '../../core/money/money.dart';
import '../../core/utils/dates.dart';
import '../models/app_user.dart';
import '../models/enums.dart';
import '../models/fin_transaction.dart';
import '../repositories/transaction_repository.dart';
import 'budget_alert_service.dart';

/// Datos de entrada del formulario de movimientos.
class TransactionDraft {
  const TransactionDraft({
    required this.type,
    required this.amount,
    required this.categoryId,
    required this.date,
    this.description,
    this.paymentMethod = PaymentMethod.cash,
    this.receiptLocalPath,
    this.recurringId,
  });

  final TxType type;
  final Money amount;
  final String categoryId;
  final DateTime date;
  final String? description;
  final PaymentMethod paymentMethod;
  final String? receiptLocalPath;
  final String? recurringId;
}

/// Resultado de guardar: el movimiento y las alertas de presupuesto generadas.
class SaveResult {
  const SaveResult(this.transaction, this.alerts);

  final FinTransaction transaction;
  final List<String> alerts;
}

/// Reglas de negocio de movimientos (validación + presupuestos + comprobantes).
class TransactionService {
  TransactionService(this._repo, this._alerts);

  final TransactionRepository _repo;
  final BudgetAlertService _alerts;
  static const _uuid = Uuid();

  static void validate(TransactionDraft d) {
    if (!d.amount.isPositive) {
      throw const ValidationException('El monto debe ser mayor que cero.');
    }
    if (d.categoryId.isEmpty) {
      throw const ValidationException('Selecciona una categoría.');
    }
    if ((d.description?.length ?? 0) > 200) {
      throw const ValidationException('La descripción admite máximo 200 caracteres.');
    }
  }

  Future<SaveResult> create(AppUser user, TransactionDraft draft) async {
    validate(draft);
    final now = DateTime.now().toUtc();
    final tx = FinTransaction(
      id: _uuid.v4(),
      userId: user.id,
      type: draft.type,
      amount: draft.amount,
      categoryId: draft.categoryId,
      date: Dates.dateOnly(draft.date),
      description: _clean(draft.description),
      paymentMethod: draft.paymentMethod,
      receiptLocalPath: draft.receiptLocalPath,
      recurringId: draft.recurringId,
      createdAt: now,
      updatedAt: now,
    );
    await _repo.insert(tx);
    final alerts = <String>[];
    if (tx.type == TxType.expense) {
      alerts.addAll(await _alerts.evaluate(user: user, categoryId: tx.categoryId, date: tx.date));
    }
    return SaveResult(tx, alerts);
  }

  Future<SaveResult> update(AppUser user, FinTransaction original, TransactionDraft draft) async {
    validate(draft);
    final receiptChanged = draft.receiptLocalPath != original.receiptLocalPath;
    final updated = FinTransaction(
      id: original.id,
      userId: original.userId,
      type: draft.type,
      amount: draft.amount,
      categoryId: draft.categoryId,
      date: Dates.dateOnly(draft.date),
      description: _clean(draft.description),
      paymentMethod: draft.paymentMethod,
      receiptLocalPath: draft.receiptLocalPath,
      // Si cambió la foto, se volverá a subir en la próxima sincronización.
      receiptRemotePath: receiptChanged ? null : original.receiptRemotePath,
      recurringId: original.recurringId,
      createdAt: original.createdAt,
      updatedAt: DateTime.now().toUtc(),
    );
    await _repo.update(updated);
    if (receiptChanged) await _deleteFile(original.receiptLocalPath);

    final alerts = <String>[];
    // Reevalúa el presupuesto anterior (pudo bajar) y el nuevo (pudo subir).
    if (original.type == TxType.expense &&
        (original.categoryId != updated.categoryId ||
            original.date.month != updated.date.month ||
            original.date.year != updated.date.year ||
            updated.type != TxType.expense)) {
      await _alerts.evaluate(user: user, categoryId: original.categoryId, date: original.date);
    }
    if (updated.type == TxType.expense) {
      alerts.addAll(await _alerts.evaluate(user: user, categoryId: updated.categoryId, date: updated.date));
    }
    return SaveResult(updated, alerts);
  }

  Future<void> delete(AppUser user, FinTransaction tx) async {
    await _repo.softDelete(tx.id);
    await _deleteFile(tx.receiptLocalPath);
    if (tx.type == TxType.expense) {
      await _alerts.evaluate(user: user, categoryId: tx.categoryId, date: tx.date);
    }
  }

  static String? _clean(String? s) {
    final t = s?.trim();
    return (t == null || t.isEmpty) ? null : t;
  }

  static Future<void> _deleteFile(String? path) async {
    if (path == null) return;
    try {
      final f = File(path);
      if (await f.exists()) await f.delete();
    } catch (_) {
      // El archivo puede no existir; no es crítico.
    }
  }
}
