/// Error de negocio con mensaje listo para mostrar al usuario.
class AppException implements Exception {
  const AppException(this.message, {this.code});

  final String message;
  final String? code;

  @override
  String toString() => message;
}

class ValidationException extends AppException {
  const ValidationException(super.message, {super.code});
}

class AuthFailure extends AppException {
  const AuthFailure(super.message, {super.code});
}
