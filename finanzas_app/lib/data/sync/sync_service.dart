import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/db/local_database.dart';
import '../../core/errors/error_handler.dart';
import '../../core/money/money.dart';
import '../../core/services/connectivity_service.dart';
import '../models/app_user.dart';
import '../models/enums.dart';
import '../repositories/data_change_bus.dart';
import '../repositories/user_repository.dart';

enum SyncPhase { disabled, idle, syncing, success, offline, error }

@immutable
class SyncState {
  const SyncState(this.phase, {this.lastSyncAt, this.message});

  final SyncPhase phase;
  final DateTime? lastSyncAt;
  final String? message;

  String get label => switch (phase) {
        SyncPhase.disabled => 'Modo local (sin nube)',
        SyncPhase.idle => 'Pendiente de sincronizar',
        SyncPhase.syncing => 'Sincronizando…',
        SyncPhase.success => 'Sincronizado',
        SyncPhase.offline => 'Sin conexión: los cambios se guardan en el dispositivo',
        SyncPhase.error => 'Error al sincronizar${message == null ? '' : ': $message'}',
      };
}

/// Configuración de mapeo de una tabla entre SQLite y Supabase.
class _TableSpec {
  const _TableSpec({
    required this.local,
    required this.remote,
    required this.select,
    required this.toRemote,
    required this.toLocal,
    required this.event,
  });

  final String local;
  final String remote;
  final String select;
  final Map<String, dynamic> Function(Map<String, Object?> row) toRemote;
  final Map<String, Object?> Function(Map<String, dynamic> row) toLocal;
  final ChangedTable event;
}

String _ts(Object? v) => DateTime.parse(v! as String).toUtc().toIso8601String();
String? _tsOrNull(Object? v) => v == null ? null : _ts(v);
String _date(Object? v) => (v! as String).substring(0, 10);
String? _dateOrNull(Object? v) => v == null ? null : _date(v);

/// Sincronización bidireccional SQLite ↔ Supabase (last-write-wins por `updated_at`).
class SyncService {
  SyncService({
    required LocalDatabase local,
    required DataChangeBus bus,
    required UserRepository users,
    required ConnectivityService connectivity,
    SupabaseClient? client,
  })  : _local = local,
        _bus = bus,
        _users = users,
        _connectivity = connectivity,
        _client = client;

  final LocalDatabase _local;
  final DataChangeBus _bus;
  final UserRepository _users;
  final ConnectivityService _connectivity;
  final SupabaseClient? _client;

  static const receiptsBucket = 'receipts';
  static const _pageSize = 500;

  final ValueNotifier<SyncState> state = ValueNotifier(const SyncState(SyncPhase.disabled));

  AppUser? _user;
  StreamSubscription<DataChange>? _busSub;
  StreamSubscription<bool>? _connSub;
  Timer? _debounce;
  bool _running = false;
  bool _runAgain = false;

  Database get _db => _local.db;

  bool get isEnabled => _client != null && (_user?.isRemote ?? false);

  static final List<_TableSpec> _specs = [
    _TableSpec(
      local: 'categories',
      remote: 'categories',
      select: 'id,user_id,name,type,color,icon,is_default,created_at,updated_at,deleted_at',
      event: ChangedTable.categories,
      toRemote: (r) => {
        'id': r['id'],
        'user_id': r['user_id'],
        'name': r['name'],
        'type': r['type'],
        'color': r['color'],
        'icon': r['icon'],
        'is_default': r['is_default'] == 1,
        'created_at': r['created_at'],
        'updated_at': r['updated_at'],
        'deleted_at': r['deleted_at'],
      },
      toLocal: (r) => {
        'id': r['id'],
        'user_id': r['user_id'],
        'name': r['name'],
        'type': r['type'],
        'color': (r['color'] as num).toInt(),
        'icon': r['icon'],
        'is_default': r['is_default'] == true ? 1 : 0,
        'created_at': _ts(r['created_at']),
        'updated_at': _ts(r['updated_at']),
        'deleted_at': _tsOrNull(r['deleted_at']),
      },
    ),
    _TableSpec(
      local: 'recurring_transactions',
      remote: 'recurring_transactions',
      select: 'id,user_id,type,amount::text,category_id,description,payment_method,frequency,'
          'start_date,next_date,end_date,status,last_generated_at,created_at,updated_at,deleted_at',
      event: ChangedTable.recurring,
      toRemote: (r) => {
        'id': r['id'],
        'user_id': r['user_id'],
        'type': r['type'],
        'amount': Money((r['amount_cents']! as num).toInt()).toDecimalString(),
        'category_id': r['category_id'],
        'description': r['description'],
        'payment_method': r['payment_method'],
        'frequency': r['frequency'],
        'start_date': r['start_date'],
        'next_date': r['next_date'],
        'end_date': r['end_date'],
        'status': r['status'],
        'last_generated_at': r['last_generated_at'],
        'created_at': r['created_at'],
        'updated_at': r['updated_at'],
        'deleted_at': r['deleted_at'],
      },
      toLocal: (r) => {
        'id': r['id'],
        'user_id': r['user_id'],
        'type': r['type'],
        'amount_cents': Money.fromDecimal(r['amount']).cents,
        'category_id': r['category_id'],
        'description': r['description'],
        'payment_method': r['payment_method'],
        'frequency': r['frequency'],
        'start_date': _date(r['start_date']),
        'next_date': _date(r['next_date']),
        'end_date': _dateOrNull(r['end_date']),
        'status': r['status'],
        'last_generated_at': _tsOrNull(r['last_generated_at']),
        'created_at': _ts(r['created_at']),
        'updated_at': _ts(r['updated_at']),
        'deleted_at': _tsOrNull(r['deleted_at']),
      },
    ),
    _TableSpec(
      local: 'transactions',
      remote: 'transactions',
      select: 'id,user_id,type,amount::text,category_id,date,description,payment_method,'
          'receipt_path,recurring_id,created_at,updated_at,deleted_at',
      event: ChangedTable.transactions,
      toRemote: (r) => {
        'id': r['id'],
        'user_id': r['user_id'],
        'type': r['type'],
        'amount': Money((r['amount_cents']! as num).toInt()).toDecimalString(),
        'category_id': r['category_id'],
        'date': r['date'],
        'description': r['description'],
        'payment_method': r['payment_method'],
        'receipt_path': r['receipt_remote_path'],
        'recurring_id': r['recurring_id'],
        'created_at': r['created_at'],
        'updated_at': r['updated_at'],
        'deleted_at': r['deleted_at'],
      },
      toLocal: (r) => {
        'id': r['id'],
        'user_id': r['user_id'],
        'type': r['type'],
        'amount_cents': Money.fromDecimal(r['amount']).cents,
        'category_id': r['category_id'],
        'date': _date(r['date']),
        'description': r['description'],
        'payment_method': r['payment_method'],
        'receipt_remote_path': r['receipt_path'],
        'recurring_id': r['recurring_id'],
        'created_at': _ts(r['created_at']),
        'updated_at': _ts(r['updated_at']),
        'deleted_at': _tsOrNull(r['deleted_at']),
      },
    ),
    _TableSpec(
      local: 'budgets',
      remote: 'budgets',
      select: 'id,user_id,category_id,limit_amount::text,month,year,alert_80_sent,alert_100_sent,'
          'created_at,updated_at,deleted_at',
      event: ChangedTable.budgets,
      toRemote: (r) => {
        'id': r['id'],
        'user_id': r['user_id'],
        'category_id': r['category_id'],
        'limit_amount': Money((r['limit_cents']! as num).toInt()).toDecimalString(),
        'month': r['month'],
        'year': r['year'],
        'alert_80_sent': r['alert_80_sent'] == 1,
        'alert_100_sent': r['alert_100_sent'] == 1,
        'created_at': r['created_at'],
        'updated_at': r['updated_at'],
        'deleted_at': r['deleted_at'],
      },
      toLocal: (r) => {
        'id': r['id'],
        'user_id': r['user_id'],
        'category_id': r['category_id'],
        'limit_cents': Money.fromDecimal(r['limit_amount']).cents,
        'month': (r['month'] as num).toInt(),
        'year': (r['year'] as num).toInt(),
        'alert_80_sent': r['alert_80_sent'] == true ? 1 : 0,
        'alert_100_sent': r['alert_100_sent'] == true ? 1 : 0,
        'created_at': _ts(r['created_at']),
        'updated_at': _ts(r['updated_at']),
        'deleted_at': _tsOrNull(r['deleted_at']),
      },
    ),
  ];

  /// Comienza a escuchar cambios locales y de conectividad.
  void start(AppUser user) {
    stop();
    _user = user;
    if (!isEnabled) {
      state.value = const SyncState(SyncPhase.disabled);
      return;
    }
    state.value = const SyncState(SyncPhase.idle);
    _busSub = _bus.stream.where((c) => !c.fromSync).listen((_) => schedule());
    _connSub = _connectivity.onStatusChange.listen((online) {
      if (online) {
        schedule(delay: const Duration(seconds: 1));
      } else {
        state.value = SyncState(SyncPhase.offline, lastSyncAt: state.value.lastSyncAt);
      }
    });
  }

  void stop() {
    _debounce?.cancel();
    _busSub?.cancel();
    _connSub?.cancel();
    _busSub = null;
    _connSub = null;
    _user = null;
    state.value = const SyncState(SyncPhase.disabled);
  }

  /// Agenda una sincronización agrupando cambios seguidos.
  void schedule({Duration delay = const Duration(seconds: 3)}) {
    if (!isEnabled) return;
    _debounce?.cancel();
    _debounce = Timer(delay, () => syncNow());
  }

  /// Ejecuta la sincronización completa. Devuelve `true` si terminó bien.
  Future<bool> syncNow() async {
    final user = _user;
    final client = _client;
    if (user == null || client == null || !user.isRemote) return false;
    if (_running) {
      _runAgain = true;
      return false;
    }
    _running = true;
    final last = state.value.lastSyncAt;
    state.value = SyncState(SyncPhase.syncing, lastSyncAt: last);
    try {
      if (!await _connectivity.isOnline()) {
        state.value = SyncState(SyncPhase.offline, lastSyncAt: last);
        return false;
      }
      await _pushProfile(client, user.id);
      await _syncReceipts(client, user.id);
      for (final spec in _specs) {
        await _push(client, spec, user.id);
      }
      for (final spec in _specs) {
        await _pull(client, spec, user.id);
      }
      await _pullProfile(client, user.id);
      state.value = SyncState(SyncPhase.success, lastSyncAt: DateTime.now());
      return true;
    } on SocketException {
      state.value = SyncState(SyncPhase.offline, lastSyncAt: last);
      return false;
    } catch (e, st) {
      ErrorHandler.log(e, st);
      state.value = SyncState(SyncPhase.error, lastSyncAt: last, message: ErrorHandler.message(e));
      return false;
    } finally {
      _running = false;
      if (_runAgain) {
        _runAgain = false;
        schedule();
      }
    }
  }

  Future<void> _push(SupabaseClient client, _TableSpec spec, String userId) async {
    final rows = await _db.query(spec.local,
        where: 'user_id = ? AND sync_status = ?', whereArgs: [userId, SyncStatus.pending]);
    if (rows.isEmpty) return;
    for (var i = 0; i < rows.length; i += 200) {
      final chunk = rows.sublist(i, i + 200 > rows.length ? rows.length : i + 200);
      await client.from(spec.remote).upsert(chunk.map(spec.toRemote).toList());
      final batch = _db.batch();
      for (final r in chunk) {
        batch.update(spec.local, {'sync_status': SyncStatus.synced},
            where: 'id = ? AND updated_at = ?', whereArgs: [r['id'], r['updated_at']]);
      }
      await batch.commit(noResult: true);
    }
  }

  Future<void> _pull(SupabaseClient client, _TableSpec spec, String userId) async {
    final metaKey = '$userId:last_pull:${spec.local}';
    final since = await _getMeta(metaKey);
    // Solapamiento de 5 s para no perder filas confirmadas con retraso.
    final sinceTs = since == null
        ? DateTime.utc(1970)
        : DateTime.parse(since).toUtc().subtract(const Duration(seconds: 5));

    var offset = 0;
    String? maxUpdated = since;
    var changed = false;
    while (true) {
      final List<Map<String, dynamic>> page = await client
          .from(spec.remote)
          .select(spec.select)
          .eq('user_id', userId)
          .gt('updated_at', sinceTs.toIso8601String())
          .order('updated_at', ascending: true)
          .range(offset, offset + _pageSize - 1);
      for (final remote in page) {
        final row = spec.toLocal(remote);
        if (await _applyRemote(spec.local, row)) changed = true;
        final u = row['updated_at']! as String;
        if (maxUpdated == null || DateTime.parse(u).isAfter(DateTime.parse(maxUpdated))) {
          maxUpdated = u;
        }
      }
      if (page.length < _pageSize) break;
      offset += _pageSize;
    }
    if (maxUpdated != null) await _setMeta(metaKey, maxUpdated);
    if (changed) _bus.emit(spec.event, fromSync: true);
  }

  /// Inserta/actualiza una fila remota salvo que la local sea más reciente y esté pendiente.
  Future<bool> _applyRemote(String table, Map<String, Object?> row) async {
    final id = row['id']! as String;
    final existing = await _db.query(table, where: 'id = ?', whereArgs: [id], limit: 1);
    if (existing.isEmpty) {
      await _db.insert(table, {...row, 'sync_status': SyncStatus.synced});
      return true;
    }
    final local = existing.first;
    if (local['sync_status'] == SyncStatus.pending) {
      final localUpdated = DateTime.parse(local['updated_at']! as String);
      final remoteUpdated = DateTime.parse(row['updated_at']! as String);
      if (localUpdated.isAfter(remoteUpdated)) return false;
    }
    final values = Map<String, Object?>.from(row)..remove('id');
    if (table == 'transactions' && local['receipt_remote_path'] != row['receipt_remote_path']) {
      // El comprobante cambió en otro dispositivo: se descargará bajo demanda.
      values['receipt_local_path'] = null;
    }
    await _db.update(table, {...values, 'sync_status': SyncStatus.synced},
        where: 'id = ?', whereArgs: [id]);
    return true;
  }

  /// Sube comprobantes nuevos y elimina los de movimientos borrados.
  Future<void> _syncReceipts(SupabaseClient client, String userId) async {
    final storage = client.storage.from(receiptsBucket);

    final toUpload = await _db.query('transactions',
        columns: ['id', 'receipt_local_path'],
        where: 'user_id = ? AND sync_status = ? AND deleted_at IS NULL '
            'AND receipt_local_path IS NOT NULL AND receipt_remote_path IS NULL',
        whereArgs: [userId, SyncStatus.pending]);
    for (final r in toUpload) {
      final file = File(r['receipt_local_path']! as String);
      if (!await file.exists()) continue;
      final path = '$userId/${r['id']}.jpg';
      await storage.upload(path, file,
          fileOptions: const FileOptions(upsert: true, contentType: 'image/jpeg'));
      await _db.update('transactions', {'receipt_remote_path': path},
          where: 'id = ?', whereArgs: [r['id']]);
    }

    final toRemove = await _db.query('transactions',
        columns: ['id', 'receipt_remote_path'],
        where: 'user_id = ? AND sync_status = ? AND deleted_at IS NOT NULL AND receipt_remote_path IS NOT NULL',
        whereArgs: [userId, SyncStatus.pending]);
    if (toRemove.isNotEmpty) {
      await storage.remove(toRemove.map((r) => r['receipt_remote_path']! as String).toList());
      for (final r in toRemove) {
        await _db.update('transactions', {'receipt_remote_path': null},
            where: 'id = ?', whereArgs: [r['id']]);
      }
    }
  }

  Future<void> _pushProfile(SupabaseClient client, String userId) async {
    final row = await _users.pendingProfileRow(userId);
    if (row == null) return;
    await client.from('users').upsert({
      'id': row['id'],
      'email': row['email'],
      'display_name': row['display_name'],
      'currency': row['currency'],
      'theme_mode': row['theme_mode'],
      'notifications_enabled': row['notifications_enabled'] == 1,
      'budget_alerts_enabled': row['budget_alerts_enabled'] == 1,
      'recurring_reminders_enabled': row['recurring_reminders_enabled'] == 1,
      'biometric_enabled': row['biometric_enabled'] == 1,
    });
    await _users.markProfileSynced(userId, row['updated_at']! as String);
  }

  Future<void> _pullProfile(SupabaseClient client, String userId) async {
    final remote = await client.from('users').select().eq('id', userId).maybeSingle();
    if (remote != null) await _users.applyRemoteProfile(userId, remote);
  }

  /// URL firmada temporal para ver un comprobante almacenado en la nube.
  Future<String?> receiptUrl(String remotePath) async {
    final client = _client;
    if (client == null) return null;
    try {
      return await client.storage.from(receiptsBucket).createSignedUrl(remotePath, 3600);
    } catch (e, st) {
      ErrorHandler.log(e, st);
      return null;
    }
  }

  /// Elimina en la nube los datos del usuario (borrado lógico + comprobantes).
  Future<void> deleteRemoteData(String userId) async {
    final client = _client;
    if (client == null) return;
    await client.rpc('delete_my_data');
    final storage = client.storage.from(receiptsBucket);
    final files = await storage.list(path: userId);
    if (files.isNotEmpty) {
      await storage.remove(files.map((f) => '$userId/${f.name}').toList());
    }
    await _db.delete('sync_meta', where: 'key LIKE ?', whereArgs: ['$userId:%']);
  }

  Future<String?> _getMeta(String key) async {
    final rows = await _db.query('sync_meta', where: 'key = ?', whereArgs: [key], limit: 1);
    return rows.isEmpty ? null : rows.first['value'] as String?;
  }

  Future<void> _setMeta(String key, String value) async {
    await _db.insert('sync_meta', {'key': key, 'value': value},
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  void dispose() {
    stop();
    state.dispose();
  }
}
