import 'package:sqflite/sqflite.dart';

import '../../core/db/local_database.dart';
import '../models/app_user.dart';
import '../models/enums.dart';
import 'data_change_bus.dart';

/// Credenciales locales (solo cuentas en modo local).
class LocalCredentials {
  const LocalCredentials({
    required this.user,
    required this.passwordHash,
    required this.passwordSalt,
    this.recoveryHash,
  });

  final AppUser user;
  final String passwordHash;
  final String passwordSalt;
  final String? recoveryHash;
}

class UserRepository {
  UserRepository(this._local, this._bus);

  final LocalDatabase _local;
  final DataChangeBus _bus;

  Database get _db => _local.db;

  Future<AppUser?> getById(String id) async {
    final rows = await _db.query('users', where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : AppUser.fromDb(rows.first);
  }

  Future<LocalCredentials?> getCredentialsByEmail(String email) async {
    final rows = await _db.query(
      'users',
      where: 'email = ? AND is_remote = 0',
      whereArgs: [email.trim().toLowerCase()],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final row = rows.first;
    return LocalCredentials(
      user: AppUser.fromDb(row),
      passwordHash: row['password_hash'] as String? ?? '',
      passwordSalt: row['password_salt'] as String? ?? '',
      recoveryHash: row['recovery_hash'] as String?,
    );
  }

  Future<bool> emailExists(String email) async {
    final rows = await _db.query('users',
        columns: ['id'], where: 'email = ?', whereArgs: [email.trim().toLowerCase()], limit: 1);
    return rows.isNotEmpty;
  }

  Future<void> insert(
    AppUser user, {
    String? passwordHash,
    String? passwordSalt,
    String? recoveryHash,
    String syncStatus = SyncStatus.synced,
  }) async {
    await _db.insert(
      'users',
      {
        'id': user.id,
        'email': user.email.trim().toLowerCase(),
        'display_name': user.displayName,
        'password_hash': passwordHash,
        'password_salt': passwordSalt,
        'recovery_hash': recoveryHash,
        'is_remote': user.isRemote ? 1 : 0,
        ..._settingsToRow(user.settings),
        'created_at': user.createdAt.toUtc().toIso8601String(),
        'updated_at': user.updatedAt.toUtc().toIso8601String(),
        'sync_status': syncStatus,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    _bus.emit(ChangedTable.users);
  }

  Future<AppUser> updateProfile(AppUser user, {String? displayName, UserSettings? settings}) async {
    final updated = user.copyWith(
      displayName: displayName,
      settings: settings,
      updatedAt: DateTime.now().toUtc(),
    );
    await _db.update(
      'users',
      {
        'display_name': updated.displayName,
        ..._settingsToRow(updated.settings),
        'updated_at': updated.updatedAt.toIso8601String(),
        'sync_status': user.isRemote ? SyncStatus.pending : SyncStatus.synced,
      },
      where: 'id = ?',
      whereArgs: [user.id],
    );
    _bus.emit(ChangedTable.users);
    return updated;
  }

  Future<void> updatePassword(String userId, {required String hash, required String salt}) async {
    await _db.update(
      'users',
      {'password_hash': hash, 'password_salt': salt, 'updated_at': DateTime.now().toUtc().toIso8601String()},
      where: 'id = ?',
      whereArgs: [userId],
    );
  }

  /// Aplica el perfil remoto si no hay cambios locales pendientes.
  Future<AppUser?> applyRemoteProfile(String userId, Map<String, dynamic> remote) async {
    final rows = await _db.query('users', where: 'id = ?', whereArgs: [userId], limit: 1);
    if (rows.isEmpty) return null;
    if (rows.first['sync_status'] == SyncStatus.pending) return AppUser.fromDb(rows.first);
    final settings = UserSettings.fromJson(remote);
    await _db.update(
      'users',
      {
        'display_name': remote['display_name'] as String?,
        ..._settingsToRow(settings),
        'updated_at': (remote['updated_at'] as String?) ?? DateTime.now().toUtc().toIso8601String(),
        'sync_status': SyncStatus.synced,
      },
      where: 'id = ?',
      whereArgs: [userId],
    );
    _bus.emit(ChangedTable.users, fromSync: true);
    return getById(userId);
  }

  Future<Map<String, Object?>?> pendingProfileRow(String userId) async {
    final rows = await _db.query('users',
        where: 'id = ? AND sync_status = ?', whereArgs: [userId, SyncStatus.pending], limit: 1);
    return rows.isEmpty ? null : rows.first;
  }

  Future<void> markProfileSynced(String userId, String updatedAt) async {
    await _db.update('users', {'sync_status': SyncStatus.synced},
        where: 'id = ? AND updated_at = ?', whereArgs: [userId, updatedAt]);
  }

  Map<String, Object?> _settingsToRow(UserSettings s) => {
        'currency': s.currency,
        'theme_mode': s.themeMode.code,
        'notifications_enabled': s.notificationsEnabled ? 1 : 0,
        'budget_alerts_enabled': s.budgetAlertsEnabled ? 1 : 0,
        'recurring_reminders_enabled': s.recurringRemindersEnabled ? 1 : 0,
        'biometric_enabled': s.biometricEnabled ? 1 : 0,
      };
}
