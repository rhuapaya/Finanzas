import 'package:sqflite/sqflite.dart';

import '../../core/db/local_database.dart';
import '../../core/utils/dates.dart';
import '../models/enums.dart';
import '../models/recurring_transaction.dart';
import 'data_change_bus.dart';

class RecurringRepository {
  RecurringRepository(this._local, this._bus);

  final LocalDatabase _local;
  final DataChangeBus _bus;

  Database get _db => _local.db;

  Future<List<RecurringTransaction>> getAll(String userId) async {
    final rows = await _db.query(
      'recurring_transactions',
      where: 'user_id = ? AND deleted_at IS NULL',
      whereArgs: [userId],
      orderBy: "CASE status WHEN 'active' THEN 0 WHEN 'paused' THEN 1 ELSE 2 END, next_date ASC",
    );
    return rows.map(RecurringTransaction.fromDb).toList();
  }

  Future<RecurringTransaction?> getById(String id) async {
    final rows = await _db.query('recurring_transactions', where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : RecurringTransaction.fromDb(rows.first);
  }

  /// Reglas activas con próxima fecha <= [today].
  Future<List<RecurringTransaction>> due(String userId, DateTime today) async {
    final rows = await _db.query(
      'recurring_transactions',
      where: "user_id = ? AND deleted_at IS NULL AND status = 'active' AND next_date <= ?",
      whereArgs: [userId, Dates.toIsoDate(today)],
    );
    return rows.map(RecurringTransaction.fromDb).toList();
  }

  Future<void> insert(RecurringTransaction r) async {
    await _db.insert('recurring_transactions', {...r.toDb(), 'sync_status': SyncStatus.pending},
        conflictAlgorithm: ConflictAlgorithm.replace);
    _bus.emit(ChangedTable.recurring);
  }

  Future<RecurringTransaction> update(RecurringTransaction r) async {
    final updated = r.copyWith(updatedAt: DateTime.now().toUtc());
    await _db.update('recurring_transactions', {...updated.toDb(), 'sync_status': SyncStatus.pending},
        where: 'id = ?', whereArgs: [r.id]);
    _bus.emit(ChangedTable.recurring);
    return updated;
  }

  Future<void> softDelete(String id) async {
    final now = DateTime.now().toUtc().toIso8601String();
    await _db.update('recurring_transactions',
        {'deleted_at': now, 'updated_at': now, 'sync_status': SyncStatus.pending},
        where: 'id = ?', whereArgs: [id]);
    _bus.emit(ChangedTable.recurring);
  }

  Future<void> upsertRaw(RecurringTransaction r) async {
    await _db.insert('recurring_transactions', {...r.toDb(), 'sync_status': SyncStatus.pending},
        conflictAlgorithm: ConflictAlgorithm.replace);
  }
}
