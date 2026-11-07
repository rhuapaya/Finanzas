import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

import '../../core/db/local_database.dart';
import '../../core/money/money.dart';
import '../../core/utils/date_range.dart';
import '../models/enums.dart';
import '../models/fin_transaction.dart';
import 'data_change_bus.dart';

/// Filtros de búsqueda de movimientos.
@immutable
class TransactionFilter {
  const TransactionFilter({this.range, this.type, this.categoryId, this.paymentMethod, this.query});

  final DateRange? range;
  final TxType? type;
  final String? categoryId;
  final PaymentMethod? paymentMethod;
  final String? query;

  bool get hasExtraFilters =>
      type != null || categoryId != null || paymentMethod != null || (query?.isNotEmpty ?? false);

  TransactionFilter copyWith({
    DateRange? range,
    TxType? type,
    String? categoryId,
    PaymentMethod? paymentMethod,
    String? query,
    bool clearType = false,
    bool clearCategory = false,
    bool clearPaymentMethod = false,
  }) =>
      TransactionFilter(
        range: range ?? this.range,
        type: clearType ? null : (type ?? this.type),
        categoryId: clearCategory ? null : (categoryId ?? this.categoryId),
        paymentMethod: clearPaymentMethod ? null : (paymentMethod ?? this.paymentMethod),
        query: query ?? this.query,
      );

  TransactionFilter clearExtras() => TransactionFilter(range: range);

  @override
  bool operator ==(Object other) =>
      other is TransactionFilter &&
      other.range == range &&
      other.type == type &&
      other.categoryId == categoryId &&
      other.paymentMethod == paymentMethod &&
      other.query == query;

  @override
  int get hashCode => Object.hash(range, type, categoryId, paymentMethod, query);
}

class TransactionRepository {
  TransactionRepository(this._local, this._bus);

  final LocalDatabase _local;
  final DataChangeBus _bus;

  Database get _db => _local.db;

  Future<List<FinTransaction>> query(String userId, TransactionFilter filter, {int? limit}) async {
    final where = StringBuffer('user_id = ? AND deleted_at IS NULL');
    final args = <Object?>[userId];
    if (filter.range != null) {
      where.write(' AND date >= ? AND date <= ?');
      args
        ..add(filter.range!.startIso)
        ..add(filter.range!.endIso);
    }
    if (filter.type != null) {
      where.write(' AND type = ?');
      args.add(filter.type!.code);
    }
    if (filter.categoryId != null) {
      where.write(' AND category_id = ?');
      args.add(filter.categoryId);
    }
    if (filter.paymentMethod != null) {
      where.write(' AND payment_method = ?');
      args.add(filter.paymentMethod!.code);
    }
    final q = filter.query?.trim();
    if (q != null && q.isNotEmpty) {
      where.write(' AND description LIKE ?');
      args.add('%$q%');
    }
    final rows = await _db.query(
      'transactions',
      where: where.toString(),
      whereArgs: args,
      orderBy: 'date DESC, created_at DESC',
      limit: limit,
    );
    return rows.map(FinTransaction.fromDb).toList();
  }

  Future<List<FinTransaction>> recent(String userId, {int limit = 5}) =>
      query(userId, const TransactionFilter(), limit: limit);

  Future<FinTransaction?> getById(String id) async {
    final rows = await _db.query('transactions', where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : FinTransaction.fromDb(rows.first);
  }

  /// Saldo total: ingresos − egresos (todas las fechas).
  Future<Money> balance(String userId) async {
    final r = await _db.rawQuery('''
      SELECT COALESCE(SUM(CASE WHEN type = 'income' THEN amount_cents ELSE -amount_cents END), 0) AS total
      FROM transactions WHERE user_id = ? AND deleted_at IS NULL
    ''', [userId]);
    return Money((r.first['total'] as num?)?.toInt() ?? 0);
  }

  /// Gasto (o ingreso) acumulado de una categoría en un mes.
  Future<Money> sumForCategoryMonth(String userId, String categoryId, int year, int month,
      {TxType type = TxType.expense}) async {
    final range = DateRange.forPeriod(PeriodType.month, DateTime(year, month));
    final r = await _db.rawQuery('''
      SELECT COALESCE(SUM(amount_cents), 0) AS total FROM transactions
      WHERE user_id = ? AND category_id = ? AND type = ? AND deleted_at IS NULL
        AND date >= ? AND date <= ?
    ''', [userId, categoryId, type.code, range.startIso, range.endIso]);
    return Money((r.first['total'] as num?)?.toInt() ?? 0);
  }

  /// Gasto por categoría de un mes (para presupuestos), en una sola consulta.
  Future<Map<String, Money>> expensesByCategoryForMonth(String userId, int year, int month) async {
    final range = DateRange.forPeriod(PeriodType.month, DateTime(year, month));
    final rows = await _db.rawQuery('''
      SELECT category_id, SUM(amount_cents) AS total FROM transactions
      WHERE user_id = ? AND type = 'expense' AND deleted_at IS NULL AND date >= ? AND date <= ?
      GROUP BY category_id
    ''', [userId, range.startIso, range.endIso]);
    return {
      for (final r in rows) r['category_id']! as String: Money((r['total'] as num?)?.toInt() ?? 0),
    };
  }

  Future<void> insert(FinTransaction tx) async {
    await _db.insert('transactions', {...tx.toDb(), 'sync_status': SyncStatus.pending},
        conflictAlgorithm: ConflictAlgorithm.replace);
    _bus.emit(ChangedTable.transactions);
  }

  Future<void> insertMany(List<FinTransaction> txs) async {
    if (txs.isEmpty) return;
    final batch = _db.batch();
    for (final tx in txs) {
      batch.insert('transactions', {...tx.toDb(), 'sync_status': SyncStatus.pending},
          conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
    _bus.emit(ChangedTable.transactions);
  }

  Future<void> update(FinTransaction tx) async {
    await _db.update('transactions', {...tx.toDb(), 'sync_status': SyncStatus.pending},
        where: 'id = ?', whereArgs: [tx.id]);
    _bus.emit(ChangedTable.transactions);
  }

  Future<void> softDelete(String id) async {
    final now = DateTime.now().toUtc().toIso8601String();
    await _db.update(
      'transactions',
      {'deleted_at': now, 'updated_at': now, 'sync_status': SyncStatus.pending},
      where: 'id = ?',
      whereArgs: [id],
    );
    _bus.emit(ChangedTable.transactions);
  }

  /// Actualiza la ruta remota del comprobante sin alterar `updated_at`.
  Future<void> setReceiptRemotePath(String id, String? remotePath) async {
    await _db.update('transactions', {'receipt_remote_path': remotePath},
        where: 'id = ?', whereArgs: [id]);
  }

  Future<int> countAll(String userId) async {
    final r = await _db.rawQuery(
        'SELECT COUNT(*) AS c FROM transactions WHERE user_id = ? AND deleted_at IS NULL', [userId]);
    return (r.first['c'] as int?) ?? 0;
  }
}
