import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Almacenamiento clave-valor cifrado (Keychain / EncryptedSharedPreferences).
abstract class SecureStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

class FlutterSecureStore implements SecureStore {
  const FlutterSecureStore();

  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock_this_device),
  );

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) => _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

/// Implementación en memoria para pruebas.
class InMemorySecureStore implements SecureStore {
  final Map<String, String> _data = {};

  @override
  Future<String?> read(String key) async => _data[key];

  @override
  Future<void> write(String key, String value) async {
    _data[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    _data.remove(key);
  }
}

/// Persiste la sesión de Supabase en almacenamiento seguro en vez de
/// SharedPreferences (texto plano).
class SecureSupabaseSessionStorage implements LocalStorage {
  const SecureSupabaseSessionStorage([this._store = const FlutterSecureStore()]);

  final SecureStore _store;
  static const _key = 'supabase_session';

  @override
  Future<void> initialize() async {}

  @override
  Future<bool> hasAccessToken() async => (await _store.read(_key)) != null;

  @override
  Future<String?> accessToken() => _store.read(_key);

  @override
  Future<void> removePersistedSession() => _store.delete(_key);

  @override
  Future<void> persistSession(String persistSessionString) =>
      _store.write(_key, persistSessionString);
}
