import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../../core/db/local_database.dart';
import '../../core/errors/app_exception.dart';
import '../models/category.dart';
import '../models/enums.dart';
import '../seed/default_categories.dart';
import 'data_change_bus.dart';

class CategoryRepository {
  CategoryRepository(this._local, this._bus);

  final LocalDatabase _local;
  final DataChangeBus _bus;
  static const _uuid = Uuid();

  Database get _db => _local.db;

  Future<List<Category>> getAll(String userId, {TxType? type}) async {
    final where = StringBuffer('user_id = ? AND deleted_at IS NULL');
    final args = <Object?>[userId];
    if (type != null) {
      where.write(' AND type = ?');
      args.add(type.code);
    }
    final rows = await _db.query(
      'categories',
      where: where.toString(),
      whereArgs: args,
      orderBy: 'is_default DESC, name COLLATE NOCASE ASC',
    );
    return rows.map(Category.fromDb).toList();
  }

  Future<Category?> getById(String id) async {
    final rows = await _db.query('categories', where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : Category.fromDb(rows.first);
  }

  Future<int> count(String userId) async {
    final r = await _db.rawQuery(
        'SELECT COUNT(*) AS c FROM categories WHERE user_id = ? AND deleted_at IS NULL', [userId]);
    return (r.first['c'] as int?) ?? 0;
  }

  Future<bool> nameExists(String userId, String name, TxType type, {String? excludeId}) async {
    final rows = await _db.rawQuery(
      'SELECT id FROM categories WHERE user_id = ? AND type = ? AND deleted_at IS NULL '
      'AND LOWER(TRIM(name)) = LOWER(TRIM(?)) ${excludeId != null ? 'AND id <> ?' : ''} LIMIT 1',
      [userId, type.code, name, if (excludeId != null) excludeId],
    );
    return rows.isNotEmpty;
  }

  /// Crea una categoría nueva.
  Future<Category> create({
    required String userId,
    required String name,
    required TxType type,
    required int color,
    required String icon,
    bool isDefault = false,
  }) async {
    final trimmed = name.trim();
    if (await nameExists(userId, trimmed, type)) {
      throw const ValidationException('Ya existe una categoría con ese nombre.');
    }
    final now = DateTime.now().toUtc();
    final category = Category(
      id: _uuid.v4(),
      userId: userId,
      name: trimmed,
      type: type,
      color: color,
      icon: icon,
      isDefault: isDefault,
      createdAt: now,
      updatedAt: now,
    );
    await _db.insert('categories', {...category.toDb(), 'sync_status': SyncStatus.pending});
    _bus.emit(ChangedTable.categories);
    return category;
  }

  Future<Category> update(Category category) async {
    final trimmed = category.name.trim();
    if (await nameExists(category.userId, trimmed, category.type, excludeId: category.id)) {
      throw const ValidationException('Ya existe una categoría con ese nombre.');
    }
    final updated = category.copyWith(name: trimmed, updatedAt: DateTime.now().toUtc());
    await _db.update(
      'categories',
      {...updated.toDb(), 'sync_status': SyncStatus.pending},
      where: 'id = ?',
      whereArgs: [category.id],
    );
    _bus.emit(ChangedTable.categories);
    return updated;
  }

  /// Cantidad de registros activos (movimientos, presupuestos, recurrentes) que usan la categoría.
  Future<int> usageCount(String categoryId) async {
    final r = await _db.rawQuery('''
      SELECT
        (SELECT COUNT(*) FROM transactions WHERE category_id = ? AND deleted_at IS NULL) +
        (SELECT COUNT(*) FROM recurring_transactions WHERE category_id = ? AND deleted_at IS NULL) +
        (SELECT COUNT(*) FROM budgets WHERE category_id = ? AND deleted_at IS NULL) AS c
    ''', [categoryId, categoryId, categoryId]);
    return (r.first['c'] as int?) ?? 0;
  }

  /// Elimina una categoría sin uso. Si tiene registros asociados lanza
  /// [ValidationException]: primero se deben reasignar.
  Future<void> delete(String categoryId) async {
    if (await usageCount(categoryId) > 0) {
      throw const ValidationException(
          'La categoría tiene movimientos asociados. Reasígnalos antes de eliminarla.');
    }
    final now = DateTime.now().toUtc().toIso8601String();
    await _db.update(
      'categories',
      {'deleted_at': now, 'updated_at': now, 'sync_status': SyncStatus.pending},
      where: 'id = ?',
      whereArgs: [categoryId],
    );
    _bus.emit(ChangedTable.categories);
  }

  /// Reasigna movimientos y recurrentes a [targetId] y elimina la categoría.
  /// Los presupuestos de la categoría eliminada se fusionan en el destino si
  /// este no tiene presupuesto ese mes; si ya lo tiene, se eliminan.
  Future<void> reassignAndDelete(String categoryId, String targetId) async {
    if (categoryId == targetId) {
      throw const ValidationException('Elige una categoría distinta.');
    }
    final source = await getById(categoryId);
    final target = await getById(targetId);
    if (source == null || target == null || target.deletedAt != null) {
      throw const AppException('Categoría no encontrada.');
    }
    if (source.type != target.type) {
      throw const ValidationException('La categoría destino debe ser del mismo tipo.');
    }
    final now = DateTime.now().toUtc().toIso8601String();
    await _db.transaction((txn) async {
      final changes = {'category_id': targetId, 'updated_at': now, 'sync_status': SyncStatus.pending};
      await txn.update('transactions', changes,
          where: 'category_id = ? AND deleted_at IS NULL', whereArgs: [categoryId]);
      await txn.update('recurring_transactions', changes,
          where: 'category_id = ? AND deleted_at IS NULL', whereArgs: [categoryId]);

      final budgets = await txn.query('budgets',
          where: 'category_id = ? AND deleted_at IS NULL', whereArgs: [categoryId]);
      for (final b in budgets) {
        final clash = await txn.query('budgets',
            columns: ['id'],
            where: 'category_id = ? AND year = ? AND month = ? AND deleted_at IS NULL',
            whereArgs: [targetId, b['year'], b['month']],
            limit: 1);
        if (clash.isEmpty) {
          await txn.update('budgets', changes, where: 'id = ?', whereArgs: [b['id']]);
        } else {
          await txn.update('budgets', {'deleted_at': now, 'updated_at': now, 'sync_status': SyncStatus.pending},
              where: 'id = ?', whereArgs: [b['id']]);
        }
      }
      await txn.update(
        'categories',
        {'deleted_at': now, 'updated_at': now, 'sync_status': SyncStatus.pending},
        where: 'id = ?',
        whereArgs: [categoryId],
      );
    });
    _bus.emit(ChangedTable.categories);
    _bus.emit(ChangedTable.transactions);
    _bus.emit(ChangedTable.budgets);
  }

  /// Crea las categorías predeterminadas si el usuario no tiene ninguna.
  Future<void> seedDefaults(String userId) async {
    if (await count(userId) > 0) return;
    final now = DateTime.now().toUtc();
    final batch = _db.batch();
    for (final d in DefaultCategories.all) {
      final c = Category(
        id: _uuid.v4(),
        userId: userId,
        name: d.name,
        type: d.type,
        color: d.color,
        icon: d.icon,
        isDefault: true,
        createdAt: now,
        updatedAt: now,
      );
      batch.insert('categories', {...c.toDb(), 'sync_status': SyncStatus.pending});
    }
    await batch.commit(noResult: true);
    _bus.emit(ChangedTable.categories);
  }

  /// Inserta/actualiza tal cual (importación de copias de seguridad).
  Future<void> upsertRaw(Category c) async {
    await _db.insert('categories', {...c.toDb(), 'sync_status': SyncStatus.pending},
        conflictAlgorithm: ConflictAlgorithm.replace);
  }
}
