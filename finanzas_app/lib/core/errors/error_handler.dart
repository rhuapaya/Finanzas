import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:sqflite/sqflite.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app_exception.dart';

/// Manejo centralizado de errores: traduce excepciones técnicas a mensajes
/// comprensibles y registra los detalles para depuración.
abstract final class ErrorHandler {
  static String message(Object error) {
    if (error is AppException) return error.message;
    if (error is AuthException) return _authMessage(error.message);
    if (error is PostgrestException) {
      if (error.code == '23505') return 'Ya existe un registro con esos datos.';
      if (error.code == '42501') return 'No tienes permiso para realizar esta acción.';
      return 'Error del servidor: ${error.message}';
    }
    if (error is StorageException) return 'No se pudo procesar el comprobante: ${error.message}';
    if (error is SocketException || error is HttpException) {
      return 'Sin conexión a Internet. Tus cambios se guardarán en el dispositivo.';
    }
    if (error is TimeoutException) return 'La operación tardó demasiado. Inténtalo nuevamente.';
    if (error is FormatException) return 'Formato inválido: ${error.message}';
    if (error is DatabaseException) return 'Error en la base de datos local.';
    if (error is PlatformException) return error.message ?? 'Error del dispositivo.';
    return 'Ocurrió un error inesperado. Inténtalo nuevamente.';
  }

  static String _authMessage(String raw) {
    final m = raw.toLowerCase();
    if (m.contains('invalid login') || m.contains('invalid credentials')) {
      return 'Correo o contraseña incorrectos.';
    }
    if (m.contains('email not confirmed')) {
      return 'Confirma tu correo electrónico antes de iniciar sesión.';
    }
    if (m.contains('already registered') || m.contains('already exists')) {
      return 'Ya existe una cuenta con este correo.';
    }
    if (m.contains('rate limit') || m.contains('too many')) {
      return 'Demasiados intentos. Espera unos minutos.';
    }
    if (m.contains('password')) return 'La contraseña no cumple los requisitos: $raw';
    return raw;
  }

  static void log(Object error, [StackTrace? stack]) {
    if (kDebugMode) {
      debugPrint('[Finanzas][ERROR] $error');
      if (stack != null) debugPrint(stack.toString());
    }
  }
}
