import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// Base de datos SQLite local (fuente de verdad offline).
///
/// Los importes se guardan como INTEGER en centavos. Cada tabla sincronizable
/// tiene `sync_status` ('pending' | 'synced') y `deleted_at` (borrado lógico).
class LocalDatabase {
  LocalDatabase._(this.db);

  final Database db;

  static const fileName = 'finanzas.db';
  static const _version = 1;

  static Future<LocalDatabase> open({DatabaseFactory? factory, String? path}) async {
    final dbFactory = factory ?? databaseFactory;
    final dbPath = path ?? p.join(await dbFactory.getDatabasesPath(), fileName);
    final db = await dbFactory.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: _version,
        onCreate: (db, version) => _createSchema(db),
      ),
    );
    return LocalDatabase._(db);
  }

  Future<void> close() => db.close();

  static Future<void> _createSchema(Database db) async {
    final batch = db.batch();
    batch.execute('''
      CREATE TABLE users (
        id TEXT PRIMARY KEY,
        email TEXT NOT NULL UNIQUE,
        display_name TEXT,
        password_hash TEXT,
        password_salt TEXT,
        recovery_hash TEXT,
        is_remote INTEGER NOT NULL DEFAULT 0,
        currency TEXT NOT NULL DEFAULT 'PEN',
        theme_mode TEXT NOT NULL DEFAULT 'system',
        notifications_enabled INTEGER NOT NULL DEFAULT 1,
        budget_alerts_enabled INTEGER NOT NULL DEFAULT 1,
        recurring_reminders_enabled INTEGER NOT NULL DEFAULT 1,
        biometric_enabled INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        sync_status TEXT NOT NULL DEFAULT 'synced'
      )''');
    batch.execute('''
      CREATE TABLE categories (
        id TEXT PRIMARY KEY,
        user_id TEXT NOT NULL,
        name TEXT NOT NULL,
        type TEXT NOT NULL CHECK (type IN ('income','expense')),
        color INTEGER NOT NULL,
        icon TEXT NOT NULL,
        is_default INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        deleted_at TEXT,
        sync_status TEXT NOT NULL DEFAULT 'pending'
      )''');
    batch.execute('CREATE INDEX idx_categories_user ON categories(user_id, type)');
    batch.execute('''
      CREATE TABLE transactions (
        id TEXT PRIMARY KEY,
        user_id TEXT NOT NULL,
        type TEXT NOT NULL CHECK (type IN ('income','expense')),
        amount_cents INTEGER NOT NULL CHECK (amount_cents > 0),
        category_id TEXT NOT NULL,
        date TEXT NOT NULL,
        description TEXT,
        payment_method TEXT NOT NULL DEFAULT 'cash',
        receipt_local_path TEXT,
        receipt_remote_path TEXT,
        recurring_id TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        deleted_at TEXT,
        sync_status TEXT NOT NULL DEFAULT 'pending'
      )''');
    batch.execute('CREATE INDEX idx_transactions_user_date ON transactions(user_id, date)');
    batch.execute('CREATE INDEX idx_transactions_category ON transactions(category_id)');
    batch.execute('''
      CREATE TABLE budgets (
        id TEXT PRIMARY KEY,
        user_id TEXT NOT NULL,
        category_id TEXT NOT NULL,
        limit_cents INTEGER NOT NULL CHECK (limit_cents > 0),
        month INTEGER NOT NULL CHECK (month BETWEEN 1 AND 12),
        year INTEGER NOT NULL,
        alert_80_sent INTEGER NOT NULL DEFAULT 0,
        alert_100_sent INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        deleted_at TEXT,
        sync_status TEXT NOT NULL DEFAULT 'pending'
      )''');
    batch.execute('CREATE INDEX idx_budgets_user_period ON budgets(user_id, year, month)');
    batch.execute('''
      CREATE TABLE recurring_transactions (
        id TEXT PRIMARY KEY,
        user_id TEXT NOT NULL,
        type TEXT NOT NULL CHECK (type IN ('income','expense')),
        amount_cents INTEGER NOT NULL CHECK (amount_cents > 0),
        category_id TEXT NOT NULL,
        description TEXT,
        payment_method TEXT NOT NULL DEFAULT 'cash',
        frequency TEXT NOT NULL,
        start_date TEXT NOT NULL,
        next_date TEXT NOT NULL,
        end_date TEXT,
        status TEXT NOT NULL DEFAULT 'active',
        last_generated_at TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        deleted_at TEXT,
        sync_status TEXT NOT NULL DEFAULT 'pending'
      )''');
    batch.execute('CREATE INDEX idx_recurring_user ON recurring_transactions(user_id, status)');
    batch.execute('''
      CREATE TABLE sync_meta (
        key TEXT PRIMARY KEY,
        value TEXT
      )''');
    await batch.commit(noResult: true);
  }

  /// Elimina todos los datos de un usuario (excepto su perfil).
  Future<void> wipeUserData(String userId) async {
    await db.transaction((txn) async {
      for (final table in const ['transactions', 'budgets', 'recurring_transactions', 'categories']) {
        await txn.delete(table, where: 'user_id = ?', whereArgs: [userId]);
      }
      await txn.delete('sync_meta', where: 'key LIKE ?', whereArgs: ['$userId:%']);
    });
  }
}
