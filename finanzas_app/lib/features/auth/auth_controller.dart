import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/errors/error_handler.dart';
import '../../core/services/biometric_service.dart';
import '../../data/models/app_user.dart';
import '../../data/repositories/auth_repository.dart';
import '../../data/repositories/user_repository.dart';

enum AuthStatus { unknown, unauthenticated, locked, authenticated }

/// Acciones que se ejecutan al entrar/salir de la sesión.
class SessionHooks {
  const SessionHooks({required this.onSignedIn, required this.onSignedOut});

  final Future<void> Function(AppUser user) onSignedIn;
  final Future<void> Function() onSignedOut;

  static final SessionHooks none = SessionHooks(onSignedIn: (_) async {}, onSignedOut: () async {});
}

/// Estado global de autenticación (usado también por el router para redirigir).
class AuthController extends ChangeNotifier {
  AuthController({
    required AuthRepository repository,
    required UserRepository users,
    required BiometricService biometric,
    SessionHooks? hooks,
  })  : _repo = repository,
        _users = users,
        _biometric = biometric,
        _hooks = hooks ?? SessionHooks.none;

  final AuthRepository _repo;
  final UserRepository _users;
  final BiometricService _biometric;
  final SessionHooks _hooks;

  AuthStatus _status = AuthStatus.unknown;
  AppUser? _user;

  AuthStatus get status => _status;
  AppUser? get user => _user;
  bool get isRemoteMode => _repo.isRemote;

  /// Restaura la sesión persistida al abrir la app.
  Future<void> init() async {
    try {
      final restored = await _repo.restoreSession();
      if (restored == null) {
        _set(AuthStatus.unauthenticated, null);
        return;
      }
      final mustLock = restored.settings.biometricEnabled && await _biometric.isAvailable();
      _set(mustLock ? AuthStatus.locked : AuthStatus.authenticated, restored);
      if (!mustLock) unawaited(_hooks.onSignedIn(restored));
    } catch (e, st) {
      ErrorHandler.log(e, st);
      _set(AuthStatus.unauthenticated, null);
    }
  }

  Future<void> signIn({required String email, required String password}) async {
    final user = await _repo.signIn(email: email, password: password);
    _enter(user);
  }

  /// Registra la cuenta. La pantalla debe llamar a [completeSignUp] después de
  /// mostrar el código de recuperación (modo local).
  Future<SignUpResult> signUp({required String email, required String password, String? displayName}) =>
      _repo.signUp(email: email, password: password, displayName: displayName);

  void completeSignUp(AppUser user) => _enter(user);

  Future<void> sendPasswordReset(String email) => _repo.sendPasswordReset(email);

  Future<void> resetWithRecoveryCode({
    required String email,
    required String recoveryCode,
    required String newPassword,
  }) =>
      _repo.resetWithRecoveryCode(email: email, recoveryCode: recoveryCode, newPassword: newPassword);

  Future<bool> unlockWithBiometrics() async {
    final ok = await _biometric.authenticate();
    if (ok && _user != null) {
      _set(AuthStatus.authenticated, _user);
      unawaited(_hooks.onSignedIn(_user!));
    }
    return ok;
  }

  Future<void> signOut() async {
    try {
      await _hooks.onSignedOut();
      await _repo.signOut();
    } catch (e, st) {
      ErrorHandler.log(e, st);
    } finally {
      _set(AuthStatus.unauthenticated, null);
    }
  }

  Future<void> updateSettings(UserSettings settings) async {
    final current = _user;
    if (current == null) return;
    _user = await _users.updateProfile(current, settings: settings);
    notifyListeners();
  }

  Future<void> updateDisplayName(String name) async {
    final current = _user;
    if (current == null) return;
    _user = await _users.updateProfile(current, displayName: name.trim());
    notifyListeners();
  }

  /// Recarga el perfil (p. ej. tras sincronizar preferencias desde la nube).
  Future<void> reloadUser() async {
    final current = _user;
    if (current == null) return;
    final fresh = await _users.getById(current.id);
    if (fresh != null) {
      _user = fresh;
      notifyListeners();
    }
  }

  void _enter(AppUser user) {
    _set(AuthStatus.authenticated, user);
    unawaited(_hooks.onSignedIn(user));
  }

  void _set(AuthStatus status, AppUser? user) {
    _status = status;
    _user = user;
    notifyListeners();
  }
}
