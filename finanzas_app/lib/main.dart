import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show Supabase, FlutterAuthClientOptions;

import 'app.dart';
import 'core/config/app_config.dart';
import 'core/db/local_database.dart';
import 'core/errors/error_handler.dart';
import 'core/security/secure_store.dart';
import 'core/services/notification_service.dart';
import 'providers.dart';

Future<void> main() async {
  runZonedGuarded<Future<void>>(() async {
    WidgetsFlutterBinding.ensureInitialized();
    FlutterError.onError = (details) {
      FlutterError.presentError(details);
      ErrorHandler.log(details.exception, details.stack);
    };

    final app = await bootstrap();
    runApp(app);
  }, (error, stack) => ErrorHandler.log(error, stack));
}

/// Inicializa dependencias y devuelve el widget raíz (reutilizado en pruebas E2E).
Future<Widget> bootstrap() async {
  await initializeDateFormatting('es');

  final prefs = await SharedPreferences.getInstance();
  var config = AppConfig.load(prefs);

  if (config.hasSupabaseCredentials) {
    try {
      await Supabase.initialize(
        url: config.supabaseUrl!,
        anonKey: config.supabaseAnonKey!,
        authOptions: const FlutterAuthClientOptions(localStorage: SecureSupabaseSessionStorage()),
      );
      config = config.markReady(true);
    } catch (e, st) {
      // Credenciales inválidas: se continúa en modo local.
      ErrorHandler.log(e, st);
    }
  }

  final db = await LocalDatabase.open();
  await NotificationService.instance.init();

  return ProviderScope(
    overrides: [
      localDatabaseProvider.overrideWithValue(db),
      sharedPreferencesProvider.overrideWithValue(prefs),
      appConfigProvider.overrideWithValue(config),
    ],
    child: const FinanzasApp(),
  );
}
