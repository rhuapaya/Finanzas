import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../../core/db/local_database.dart';
import '../../core/errors/app_exception.dart';
import '../../core/money/money.dart';
import '../models/budget.dart';
import '../models/enums.dart';
import 'data_change_bus.dart';

class BudgetRepository {
  BudgetRepository(this._local, this._bus);

  final LocalDatabase _local;
  final DataChangeBus _bus;
  static const _uuid = Uuid();

  Database get _db => _local.db;

  Future<List<Budget>> forMonth(String userId, int year, int month) async {
    final rows = await _db.query(
      'budgets',
      where: 'user_id = ? AND year = ? AND month = ? AND deleted_at IS NULL',
      whereArgs: [userId, year, month],
    );
    return rows.map(Budget.fromDb).toList();
  }

  Future<Budget?> findByCategoryMonth(String userId, String categoryId, int year, int month) async {
    final rows = await _db.query(
      'budgets',
      where: 'user_id = ? AND category_id = ? AND year = ? AND month = ? AND deleted_at IS NULL',
      whereArgs: [userId, categoryId, year, month],
      limit: 1,
    );
    return rows.isEmpty ? null : Budget.fromDb(rows.first);
  }

  Future<Budget?> getById(String id) async {
    final rows = await _db.query('budgets', where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : Budget.fromDb(rows.first);
  }

  Future<Budget> create({
    required String userId,
    required String categoryId,
    required Money limit,
    required int year,
    required int month,
  }) async {
    if (!limit.isPositive) throw const ValidationException('El monto debe ser mayor que cero.');
    if (await findByCategoryMonth(userId, categoryId, year, month) != null) {
      throw const ValidationException('Esa categoría ya tiene presupuesto para este mes.');
    }
    final now = DateTime.now().toUtc();
    final budget = Budget(
      id: _uuid.v4(),
      userId: userId,
      categoryId: categoryId,
      limit: limit,
      month: month,
      year: year,
      createdAt: now,
      updatedAt: now,
    );
    await _db.insert('budgets', {...budget.toDb(), 'sync_status': SyncStatus.pending});
    _bus.emit(ChangedTable.budgets);
    return budget;
  }

  Future<Budget> update(Budget budget) async {
    if (!budget.limit.isPositive) throw const ValidationException('El monto debe ser mayor que cero.');
    final clash = await findByCategoryMonth(budget.userId, budget.categoryId, budget.year, budget.month);
    if (clash != null && clash.id != budget.id) {
      throw const ValidationException('Esa categoría ya tiene presupuesto para este mes.');
    }
    final updated = budget.copyWith(updatedAt: DateTime.now().toUtc());
    await _db.update('budgets', {...updated.toDb(), 'sync_status': SyncStatus.pending},
        where: 'id = ?', whereArgs: [budget.id]);
    _bus.emit(ChangedTable.budgets);
    return updated;
  }

  Future<void> updateAlertFlags(String id, {required bool alert80Sent, required bool alert100Sent}) async {
    await _db.update(
      'budgets',
      {
        'alert_80_sent': alert80Sent ? 1 : 0,
        'alert_100_sent': alert100Sent ? 1 : 0,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
        'sync_status': SyncStatus.pending,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> softDelete(String id) async {
    final now = DateTime.now().toUtc().toIso8601String();
    await _db.update('budgets', {'deleted_at': now, 'updated_at': now, 'sync_status': SyncStatus.pending},
        where: 'id = ?', whereArgs: [id]);
    _bus.emit(ChangedTable.budgets);
  }

  Future<void> upsertRaw(Budget b) async {
    await _db.insert('budgets', {...b.toDb(), 'sync_status': SyncStatus.pending},
        conflictAlgorithm: ConflictAlgorithm.replace);
  }
}
