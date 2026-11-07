import 'dart:io';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../errors/error_handler.dart';

/// Abstracción para enviar alertas (permite simularlas en pruebas).
abstract class AlertNotifier {
  Future<void> notify({required int id, required String title, required String body});
}

/// Notificaciones locales del sistema (alertas de presupuesto, recurrentes).
class NotificationService implements AlertNotifier {
  NotificationService._();

  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;

  static const _channelId = 'finanzas_alerts';
  static const _channelName = 'Alertas de finanzas';
  static const _channelDescription = 'Alertas de presupuesto y movimientos recurrentes';

  Future<void> init() async {
    try {
      const android = AndroidInitializationSettings('@mipmap/ic_launcher');
      const ios = DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      );
      await _plugin.initialize(const InitializationSettings(android: android, iOS: ios));
      _ready = true;
    } catch (e, st) {
      ErrorHandler.log(e, st);
    }
  }

  /// Solicita permiso (Android 13+ / iOS). Devuelve `true` si se concedió.
  Future<bool> requestPermission() async {
    if (!_ready) return false;
    try {
      if (Platform.isAndroid) {
        final android = _plugin
            .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
        return await android?.requestNotificationsPermission() ?? false;
      }
      if (Platform.isIOS) {
        final ios =
            _plugin.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();
        return await ios?.requestPermissions(alert: true, badge: true, sound: true) ?? false;
      }
    } catch (e, st) {
      ErrorHandler.log(e, st);
    }
    return false;
  }

  @override
  Future<void> notify({required int id, required String title, required String body}) async {
    if (!_ready) return;
    try {
      const details = NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          channelDescription: _channelDescription,
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(),
      );
      await _plugin.show(id, title, body, details);
    } catch (e, st) {
      ErrorHandler.log(e, st);
    }
  }
}

/// Notificador que no hace nada (pruebas o notificaciones desactivadas).
class SilentNotifier implements AlertNotifier {
  final List<String> sent = [];

  @override
  Future<void> notify({required int id, required String title, required String body}) async {
    sent.add('$title|$body');
  }
}
