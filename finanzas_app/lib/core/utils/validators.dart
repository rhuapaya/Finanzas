import '../money/money.dart';

/// Validadores de formularios (devuelven el mensaje de error o `null`).
abstract final class Validators {
  static final _emailRegex = RegExp(r'^[\w.+\-]+@[\w\-]+(\.[\w\-]+)+$');

  static String? email(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return 'Ingresa tu correo electrónico';
    if (!_emailRegex.hasMatch(v)) return 'Correo electrónico no válido';
    return null;
  }

  static String? password(String? value) {
    final v = value ?? '';
    if (v.isEmpty) return 'Ingresa una contraseña';
    if (v.length < 8) return 'Debe tener al menos 8 caracteres';
    if (!RegExp('[A-Za-z]').hasMatch(v) || !RegExp(r'\d').hasMatch(v)) {
      return 'Debe incluir letras y números';
    }
    return null;
  }

  static String? loginPassword(String? value) =>
      (value == null || value.isEmpty) ? 'Ingresa tu contraseña' : null;

  static String? requiredField(String? value, [String field = 'Este campo']) =>
      (value == null || value.trim().isEmpty) ? '$field es obligatorio' : null;

  /// Valida que el monto sea un número válido y mayor que cero.
  static String? amount(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return 'Ingresa un monto';
    final money = Money.tryParse(v);
    if (money == null) return 'Monto no válido (máximo 2 decimales)';
    if (!money.isPositive) return 'El monto debe ser mayor que cero';
    return null;
  }

  static String? categoryName(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return 'Ingresa un nombre';
    if (v.length > 40) return 'Máximo 40 caracteres';
    return null;
  }

  static String? description(String? value) {
    if (value != null && value.length > 200) return 'Máximo 200 caracteres';
    return null;
  }
}
