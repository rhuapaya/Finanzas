import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../core/db/local_database.dart';
import '../../core/errors/app_exception.dart';
import '../models/app_user.dart';
import '../models/budget.dart';
import '../models/category.dart';
import '../models/fin_transaction.dart';
import '../models/recurring_transaction.dart';
import '../repositories/budget_repository.dart';
import '../repositories/category_repository.dart';
import '../repositories/data_change_bus.dart';
import '../repositories/recurring_repository.dart';
import '../repositories/transaction_repository.dart';

class ImportSummary {
  const ImportSummary({
    required this.categories,
    required this.transactions,
    required this.budgets,
    required this.recurring,
  });

  final int categories;
  final int transactions;
  final int budgets;
  final int recurring;

  int get total => categories + transactions + budgets + recurring;
}

/// Copia de seguridad completa en JSON (exportar / importar / eliminar).
class BackupService {
  BackupService({
    required LocalDatabase local,
    required DataChangeBus bus,
    required CategoryRepository categories,
    required TransactionRepository transactions,
    required BudgetRepository budgets,
    required RecurringRepository recurring,
  })  : _local = local,
        _bus = bus,
        _categories = categories,
        _transactions = transactions,
        _budgets = budgets,
        _recurring = recurring;

  final LocalDatabase _local;
  final DataChangeBus _bus;
  final CategoryRepository _categories;
  final TransactionRepository _transactions;
  final BudgetRepository _budgets;
  final RecurringRepository _recurring;

  static const formatVersion = 1;

  Future<Map<String, dynamic>> buildBackup(AppUser user) async {
    final db = _local.db;
    final cats = (await db.query('categories', where: 'user_id = ? AND deleted_at IS NULL', whereArgs: [user.id]))
        .map(Category.fromDb)
        .map((c) => c.toJson())
        .toList();
    final txs = (await db.query('transactions', where: 'user_id = ? AND deleted_at IS NULL', whereArgs: [user.id]))
        .map(FinTransaction.fromDb)
        .map((t) => t.toJson())
        .toList();
    final buds = (await db.query('budgets', where: 'user_id = ? AND deleted_at IS NULL', whereArgs: [user.id]))
        .map(Budget.fromDb)
        .map((b) => b.toJson())
        .toList();
    final recs = (await db.query('recurring_transactions',
            where: 'user_id = ? AND deleted_at IS NULL', whereArgs: [user.id]))
        .map(RecurringTransaction.fromDb)
        .map((r) => r.toJson())
        .toList();

    return {
      'app': 'mis_finanzas',
      'version': formatVersion,
      'exported_at': DateTime.now().toUtc().toIso8601String(),
      'settings': user.settings.toJson(),
      'categories': cats,
      'transactions': txs,
      'budgets': buds,
      'recurring_transactions': recs,
    };
  }

  Future<File> exportToFile(AppUser user) async {
    final data = await buildBackup(user);
    final dir = await getTemporaryDirectory();
    final n = DateTime.now();
    final name =
        'mis_finanzas_respaldo_${n.year}${n.month.toString().padLeft(2, '0')}${n.day.toString().padLeft(2, '0')}.json';
    final file = File(p.join(dir.path, name));
    await file.writeAsString(const JsonEncoder.withIndent('  ').convert(data));
    return file;
  }

  /// Importa una copia (fusiona por id). Los registros quedan pendientes de sincronizar.
  Future<ImportSummary> importData(AppUser user, Map<String, dynamic> data) async {
    if (data['app'] != 'mis_finanzas' || data['version'] is! int) {
      throw const ValidationException('El archivo no es una copia válida de Mis Finanzas.');
    }
    if ((data['version'] as int) > formatVersion) {
      throw const ValidationException('La copia proviene de una versión más reciente de la app.');
    }
    List<Map<String, dynamic>> list(String key) =>
        ((data[key] as List?) ?? const []).cast<Map<String, dynamic>>();

    try {
      final cats = list('categories').map((j) => Category.fromJson(j, user.id)).toList();
      final txs = list('transactions').map((j) => FinTransaction.fromJson(j, user.id)).toList();
      final buds = list('budgets').map((j) => Budget.fromJson(j, user.id)).toList();
      final recs = list('recurring_transactions').map((j) => RecurringTransaction.fromJson(j, user.id)).toList();

      final now = DateTime.now().toUtc();

      // Si ya existe una categoría activa con el mismo nombre y tipo (p. ej.
      // las predeterminadas), se reutiliza para no duplicarla.
      final existing = await _categories.getAll(user.id);
      String keyOf(Category c) => '${c.type.code}|${c.name.trim().toLowerCase()}';
      final byKey = {for (final c in existing) keyOf(c): c.id};
      final idMap = <String, String>{};
      for (final c in cats) {
        final match = byKey[keyOf(c)];
        if (match != null && match != c.id) {
          idMap[c.id] = match;
        } else {
          await _categories.upsertRaw(c.copyWith(updatedAt: now));
        }
      }
      String mapCat(String id) => idMap[id] ?? id;

      for (final r in recs) {
        await _recurring.upsertRaw(r.copyWith(categoryId: mapCat(r.categoryId), updatedAt: now));
      }
      await _transactions.insertMany(
          txs.map((t) => t.copyWith(categoryId: mapCat(t.categoryId), updatedAt: now)).toList());
      for (final b in buds) {
        final mapped = b.copyWith(categoryId: mapCat(b.categoryId), updatedAt: now);
        final clash = await _budgets.findByCategoryMonth(user.id, mapped.categoryId, mapped.year, mapped.month);
        if (clash == null || clash.id == mapped.id) await _budgets.upsertRaw(mapped);
      }
      for (final t in ChangedTable.values) {
        _bus.emit(t);
      }
      return ImportSummary(
        categories: cats.length,
        transactions: txs.length,
        budgets: buds.length,
        recurring: recs.length,
      );
    } on AppException {
      rethrow;
    } catch (_) {
      throw const ValidationException('El archivo de copia está dañado o incompleto.');
    }
  }

  Future<ImportSummary> importFromFile(AppUser user, File file) async {
    final content = await file.readAsString();
    final Object? decoded;
    try {
      decoded = jsonDecode(content);
    } on FormatException {
      throw const ValidationException('El archivo no es un JSON válido.');
    }
    if (decoded is! Map<String, dynamic>) {
      throw const ValidationException('El archivo no es una copia válida de Mis Finanzas.');
    }
    return importData(user, decoded);
  }

  /// Elimina todos los movimientos, presupuestos, recurrentes y categorías
  /// locales del usuario y restaura las categorías predeterminadas.
  Future<void> deleteAllLocalData(AppUser user) async {
    await _local.wipeUserData(user.id);
    if (!user.isRemote) await _categories.seedDefaults(user.id);
    for (final t in ChangedTable.values) {
      _bus.emit(t, fromSync: true);
    }
  }
}
