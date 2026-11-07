import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';

import '../errors/error_handler.dart';

/// Acceso biométrico (huella / rostro) con respaldo del PIN del dispositivo.
class BiometricService {
  BiometricService([LocalAuthentication? auth]) : _auth = auth ?? LocalAuthentication();

  final LocalAuthentication _auth;

  Future<bool> isAvailable() async {
    try {
      final supported = await _auth.isDeviceSupported();
      if (!supported) return false;
      return await _auth.canCheckBiometrics;
    } on PlatformException catch (e, st) {
      ErrorHandler.log(e, st);
      return false;
    }
  }

  Future<bool> authenticate({String reason = 'Confirma tu identidad para abrir Mis Finanzas'}) async {
    try {
      return await _auth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(stickyAuth: true, biometricOnly: false),
      );
    } on PlatformException catch (e, st) {
      ErrorHandler.log(e, st);
      return false;
    }
  }
}
