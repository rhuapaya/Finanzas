import '../../core/errors/error_handler.dart';
import '../models/app_user.dart';
import '../repositories/category_repository.dart';
import '../sync/sync_service.dart';
import 'recurring_service.dart';

/// Tareas al iniciar sesión, cerrarla o volver a la app.
class SessionService {
  SessionService({
    required CategoryRepository categories,
    required RecurringService recurring,
    required SyncService sync,
  })  : _categories = categories,
        _recurring = recurring,
        _sync = sync;

  final CategoryRepository _categories;
  final RecurringService _recurring;
  final SyncService _sync;

  /// Mensajes de alerta pendientes de mostrar (p. ej. generados por recurrentes).
  final List<String> pendingAlerts = [];

  Future<void> onSignedIn(AppUser user) async {
    try {
      _sync.start(user);
      if (user.isRemote) {
        final ok = await _sync.syncNow();
        // Si el servidor no tenía categorías (o es un proyecto sin el trigger), se crean.
        if (ok && await _categories.count(user.id) == 0) {
          await _categories.seedDefaults(user.id);
        }
      } else {
        await _categories.seedDefaults(user.id);
      }
      final (_, alerts) = await _recurring.processDue(user);
      pendingAlerts.addAll(alerts);
    } catch (e, st) {
      ErrorHandler.log(e, st);
    }
  }

  Future<void> onSignedOut() async => _sync.stop();

  Future<void> onResume(AppUser user) async {
    try {
      final (_, alerts) = await _recurring.processDue(user);
      pendingAlerts.addAll(alerts);
      if (_sync.isEnabled) await _sync.syncNow();
    } catch (e, st) {
      ErrorHandler.log(e, st);
    }
  }
}
