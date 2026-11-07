import 'package:finanzas_app/core/db/local_database.dart';
import 'package:finanzas_app/core/money/currency.dart';
import 'package:finanzas_app/core/money/money.dart';
import 'package:finanzas_app/core/services/biometric_service.dart';
import 'package:finanzas_app/data/models/app_user.dart';
import 'package:finanzas_app/data/models/enums.dart';
import 'package:finanzas_app/data/repositories/auth_repository.dart';
import 'package:finanzas_app/data/repositories/data_change_bus.dart';
import 'package:finanzas_app/data/repositories/user_repository.dart';
import 'package:finanzas_app/features/auth/auth_controller.dart';
import 'package:finanzas_app/features/auth/login_screen.dart';
import 'package:finanzas_app/providers.dart';
import 'package:finanzas_app/router.dart';
import 'package:finanzas_app/shared/widgets/money_widgets.dart';
import 'package:finanzas_app/shared/widgets/state_views.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _FakeAuthRepository implements AuthRepository {
  String? lastEmail;

  @override
  bool get isRemote => false;

  @override
  Future<AppUser?> restoreSession() async => null;

  @override
  Future<AppUser> signIn({required String email, required String password}) async {
    lastEmail = email;
    final now = DateTime.now();
    return AppUser(id: 'u1', email: email, createdAt: now, updatedAt: now);
  }

  @override
  Future<SignUpResult> signUp({required String email, required String password, String? displayName}) =>
      throw UnimplementedError();

  @override
  Future<void> sendPasswordReset(String email) async {}

  @override
  Future<void> resetWithRecoveryCode({
    required String email,
    required String recoveryCode,
    required String newPassword,
  }) async {}

  @override
  Future<void> signOut() async {}
}

void main() {
  group('Redirección por estado de sesión', () {
    test('sin sesión solo permite pantallas de acceso', () {
      expect(authRedirect(AuthStatus.unauthenticated, '/home'), '/login');
      expect(authRedirect(AuthStatus.unauthenticated, '/register'), isNull);
      expect(authRedirect(AuthStatus.unauthenticated, '/forgot-password'), isNull);
    });

    test('con sesión no vuelve a login', () {
      expect(authRedirect(AuthStatus.authenticated, '/login'), '/home');
      expect(authRedirect(AuthStatus.authenticated, '/splash'), '/home');
      expect(authRedirect(AuthStatus.authenticated, '/transactions'), isNull);
    });

    test('bloqueo biométrico y carga inicial', () {
      expect(authRedirect(AuthStatus.locked, '/home'), '/lock');
      expect(authRedirect(AuthStatus.unknown, '/home'), '/splash');
    });
  });

  group('AmountInputFormatter', () {
    TextEditingValue apply(String oldText, String newText) => AmountInputFormatter().formatEditUpdate(
          TextEditingValue(text: oldText),
          TextEditingValue(text: newText, selection: TextSelection.collapsed(offset: newText.length)),
        );

    test('convierte coma en punto y limita a 2 decimales', () {
      expect(apply('12', '12,').text, '12.');
      expect(apply('12.5', '12.55').text, '12.55');
      expect(apply('12.55', '12.555').text, '12.55');
      expect(apply('12', '12a').text, '12');
      expect(apply('1.5', '1.5.').text, '1.5');
    });
  });

  testWidgets('AmountText formatea en soles con signo según el tipo', (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [currencyProvider.overrideWithValue(CurrencyInfo.pen)],
      child: const MaterialApp(
        home: Scaffold(
          body: Column(children: [
            AmountText(Money(150050), type: TxType.income),
            AmountText(Money(2590), type: TxType.expense),
          ]),
        ),
      ),
    ));
    expect(find.text('+S/ 1,500.50'), findsOneWidget);
    expect(find.text('-S/ 25.90'), findsOneWidget);
  });

  testWidgets('EmptyState muestra mensaje y acción', (tester) async {
    var tapped = false;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: EmptyState(
          icon: Icons.inbox,
          title: 'Sin movimientos',
          message: 'Agrega el primero',
          actionLabel: 'Agregar',
          onAction: () => tapped = true,
        ),
      ),
    ));
    expect(find.text('Sin movimientos'), findsOneWidget);
    await tester.tap(find.text('Agregar'));
    expect(tapped, isTrue);
  });

  group('LoginScreen', () {
    late LocalDatabase db;
    late _FakeAuthRepository repo;
    late AuthController controller;

    setUpAll(sqfliteFfiInit);

    setUp(() async {
      db = await _openDb();
      repo = _FakeAuthRepository();
      controller = AuthController(
        repository: repo,
        users: UserRepository(db, DataChangeBus()),
        biometric: BiometricService(),
      );
    });

    tearDown(() => db.close());

    Widget app() => ProviderScope(
          overrides: [authControllerProvider.overrideWith((ref) => controller)],
          child: const MaterialApp(home: LoginScreen()),
        );

    testWidgets('valida los campos obligatorios', (tester) async {
      await tester.pumpWidget(app());
      await tester.tap(find.byKey(const Key('login_submit')));
      await tester.pump();
      expect(find.text('Ingresa tu correo electrónico'), findsOneWidget);
      expect(find.text('Ingresa tu contraseña'), findsOneWidget);
      expect(repo.lastEmail, isNull);
    });

    testWidgets('inicia sesión con datos válidos', (tester) async {
      await tester.pumpWidget(app());
      await tester.enterText(find.byKey(const Key('login_email')), 'ana@correo.pe');
      await tester.enterText(find.byKey(const Key('login_password')), 'clave2026');
      await tester.tap(find.byKey(const Key('login_submit')));
      await tester.pumpAndSettle();
      expect(repo.lastEmail, 'ana@correo.pe');
      expect(controller.status, AuthStatus.authenticated);
    });
  });
}

Future<LocalDatabase> _openDb() =>
    LocalDatabase.open(factory: databaseFactoryFfi, path: inMemoryDatabasePath);
