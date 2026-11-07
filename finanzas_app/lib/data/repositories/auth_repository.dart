import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../core/errors/app_exception.dart';
import '../../core/security/password_hasher.dart';
import '../../core/security/secure_store.dart';
import '../models/app_user.dart';
import '../models/enums.dart';
import 'user_repository.dart';

class SignUpResult {
  const SignUpResult({this.user, this.recoveryCode, this.needsEmailConfirmation = false});

  final AppUser? user;

  /// Código de recuperación (solo cuentas locales). Debe mostrarse una vez.
  final String? recoveryCode;
  final bool needsEmailConfirmation;
}

/// Contrato de autenticación (implementaciones local y Supabase).
abstract class AuthRepository {
  bool get isRemote;

  Future<AppUser?> restoreSession();
  Future<AppUser> signIn({required String email, required String password});
  Future<SignUpResult> signUp({required String email, required String password, String? displayName});

  /// Supabase: envía un correo. Local: no aplica (usar [resetWithRecoveryCode]).
  Future<void> sendPasswordReset(String email);

  /// Solo modo local: restablece la contraseña con el código de recuperación.
  Future<void> resetWithRecoveryCode({
    required String email,
    required String recoveryCode,
    required String newPassword,
  });

  Future<void> signOut();
}

/// Cuentas guardadas en el dispositivo (modo sin nube).
class LocalAuthRepository implements AuthRepository {
  LocalAuthRepository(this._users, this._secure);

  final UserRepository _users;
  final SecureStore _secure;
  static const _sessionKey = 'local_session_user_id';
  static const _uuid = Uuid();

  @override
  bool get isRemote => false;

  @override
  Future<AppUser?> restoreSession() async {
    final id = await _secure.read(_sessionKey);
    if (id == null) return null;
    final user = await _users.getById(id);
    if (user == null) await _secure.delete(_sessionKey);
    return user;
  }

  @override
  Future<AppUser> signIn({required String email, required String password}) async {
    final creds = await _users.getCredentialsByEmail(email);
    if (creds == null ||
        !PasswordHasher.verify(password, creds.passwordSalt, creds.passwordHash)) {
      throw const AuthFailure('Correo o contraseña incorrectos.');
    }
    await _secure.write(_sessionKey, creds.user.id);
    return creds.user;
  }

  @override
  Future<SignUpResult> signUp({required String email, required String password, String? displayName}) async {
    final normalized = email.trim().toLowerCase();
    if (await _users.emailExists(normalized)) {
      throw const AuthFailure('Ya existe una cuenta con este correo.');
    }
    final salt = PasswordHasher.generateSalt();
    final recoveryCode = PasswordHasher.generateRecoveryCode();
    final now = DateTime.now().toUtc();
    final user = AppUser(
      id: _uuid.v4(),
      email: normalized,
      displayName: displayName?.trim().isEmpty ?? true ? null : displayName!.trim(),
      createdAt: now,
      updatedAt: now,
    );
    await _users.insert(
      user,
      passwordHash: PasswordHasher.hash(password, salt),
      passwordSalt: salt,
      recoveryHash: PasswordHasher.hash(PasswordHasher.normalizeRecoveryCode(recoveryCode), salt),
    );
    await _secure.write(_sessionKey, user.id);
    return SignUpResult(user: user, recoveryCode: recoveryCode);
  }

  @override
  Future<void> sendPasswordReset(String email) async {
    throw const AuthFailure('En modo local usa tu código de recuperación.');
  }

  @override
  Future<void> resetWithRecoveryCode({
    required String email,
    required String recoveryCode,
    required String newPassword,
  }) async {
    final creds = await _users.getCredentialsByEmail(email);
    final recoveryHash = creds?.recoveryHash;
    if (creds == null ||
        recoveryHash == null ||
        !PasswordHasher.verify(
            PasswordHasher.normalizeRecoveryCode(recoveryCode), creds.passwordSalt, recoveryHash)) {
      throw const AuthFailure('Correo o código de recuperación incorrectos.');
    }
    // Se conserva la sal para que el código de recuperación siga siendo válido.
    await _users.updatePassword(
      creds.user.id,
      hash: PasswordHasher.hash(newPassword, creds.passwordSalt),
      salt: creds.passwordSalt,
    );
  }

  @override
  Future<void> signOut() => _secure.delete(_sessionKey);
}

/// Autenticación con Supabase Auth.
class SupabaseAuthRepository implements AuthRepository {
  SupabaseAuthRepository(this._client, this._users);

  final SupabaseClient _client;
  final UserRepository _users;

  @override
  bool get isRemote => true;

  @override
  Future<AppUser?> restoreSession() async {
    final user = _client.auth.currentUser;
    if (user == null || _client.auth.currentSession == null) return null;
    return _ensureLocalProfile(user);
  }

  @override
  Future<AppUser> signIn({required String email, required String password}) async {
    final res = await _client.auth.signInWithPassword(email: email.trim(), password: password);
    final user = res.user;
    if (user == null) throw const AuthFailure('No se pudo iniciar sesión.');
    return _ensureLocalProfile(user);
  }

  @override
  Future<SignUpResult> signUp({required String email, required String password, String? displayName}) async {
    final res = await _client.auth.signUp(
      email: email.trim(),
      password: password,
      data: {if (displayName != null && displayName.trim().isNotEmpty) 'display_name': displayName.trim()},
    );
    final user = res.user;
    if (user == null) throw const AuthFailure('No se pudo crear la cuenta.');
    if (res.session == null) return const SignUpResult(needsEmailConfirmation: true);
    return SignUpResult(user: await _ensureLocalProfile(user));
  }

  @override
  Future<void> sendPasswordReset(String email) => _client.auth.resetPasswordForEmail(email.trim());

  @override
  Future<void> resetWithRecoveryCode({
    required String email,
    required String recoveryCode,
    required String newPassword,
  }) async {
    throw const AuthFailure('Usa el enlace enviado a tu correo para restablecer la contraseña.');
  }

  @override
  Future<void> signOut() => _client.auth.signOut();

  Future<AppUser> _ensureLocalProfile(User user) async {
    final existing = await _users.getById(user.id);
    if (existing != null) return existing;
    final now = DateTime.now().toUtc();
    final profile = AppUser(
      id: user.id,
      email: (user.email ?? '').toLowerCase(),
      displayName: user.userMetadata?['display_name'] as String?,
      isRemote: true,
      createdAt: DateTime.tryParse(user.createdAt)?.toUtc() ?? now,
      updatedAt: now,
    );
    await _users.insert(profile, syncStatus: SyncStatus.synced);
    return profile;
  }
}
