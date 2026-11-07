import 'package:shared_preferences/shared_preferences.dart';

/// Configuración del backend.
///
/// Prioridad: `--dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...`
/// y, si no existen, los valores guardados desde Configuración › Sincronización.
/// Sin credenciales la app funciona en modo local (sin nube).
class AppConfig {
  const AppConfig({this.supabaseUrl, this.supabaseAnonKey, this.supabaseReady = false});

  static const _envUrl = String.fromEnvironment('SUPABASE_URL');
  static const _envKey = String.fromEnvironment('SUPABASE_ANON_KEY');
  static const prefsUrlKey = 'supabase_url';
  static const prefsKeyKey = 'supabase_anon_key';

  final String? supabaseUrl;
  final String? supabaseAnonKey;

  /// `true` cuando Supabase se inicializó correctamente.
  final bool supabaseReady;

  bool get hasSupabaseCredentials =>
      (supabaseUrl?.isNotEmpty ?? false) && (supabaseAnonKey?.isNotEmpty ?? false);

  bool get fromEnvironment => _envUrl.isNotEmpty && _envKey.isNotEmpty;

  AppConfig markReady(bool ready) =>
      AppConfig(supabaseUrl: supabaseUrl, supabaseAnonKey: supabaseAnonKey, supabaseReady: ready);

  static AppConfig load(SharedPreferences prefs) {
    if (_envUrl.isNotEmpty && _envKey.isNotEmpty) {
      return const AppConfig(supabaseUrl: _envUrl, supabaseAnonKey: _envKey);
    }
    return AppConfig(
      supabaseUrl: prefs.getString(prefsUrlKey),
      supabaseAnonKey: prefs.getString(prefsKeyKey),
    );
  }

  static Future<void> saveCredentials(SharedPreferences prefs, {String? url, String? anonKey}) async {
    if (url == null || url.trim().isEmpty || anonKey == null || anonKey.trim().isEmpty) {
      await prefs.remove(prefsUrlKey);
      await prefs.remove(prefsKeyKey);
      return;
    }
    await prefs.setString(prefsUrlKey, url.trim());
    await prefs.setString(prefsKeyKey, anonKey.trim());
  }
}
