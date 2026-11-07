// Flujo E2E en emulador o dispositivo (modo local):
//   flutter test integration_test/app_flow_test.dart
// Registra un usuario, agrega un egreso y verifica el panel principal.
import 'package:finanzas_app/main.dart' as app;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('registro → agregar egreso → ver saldo en el panel', (tester) async {
    final root = await app.bootstrap();
    await tester.pumpWidget(root);
    await tester.pumpAndSettle(const Duration(seconds: 2));

    // Si quedó una sesión de una ejecución anterior, se cierra.
    if (find.byKey(const Key('login_email')).evaluate().isEmpty) {
      await tester.tap(find.text('Configuración'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('Cerrar sesión').last, 300);
      await tester.tap(find.text('Cerrar sesión').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cerrar sesión').last);
      await tester.pumpAndSettle();
    }

    // Registro
    await tester.tap(find.byKey(const Key('go_register')));
    await tester.pumpAndSettle();
    final email = 'e2e${DateTime.now().millisecondsSinceEpoch}@prueba.pe';
    await tester.enterText(find.byKey(const Key('register_name')), 'Prueba E2E');
    await tester.enterText(find.byKey(const Key('register_email')), email);
    await tester.enterText(find.byKey(const Key('register_password')), 'clave2026');
    await tester.enterText(find.byKey(const Key('register_confirm')), 'clave2026');
    await tester.tap(find.byKey(const Key('register_submit')));
    await tester.pumpAndSettle(const Duration(seconds: 2));

    expect(find.byKey(const Key('recovery_code')), findsOneWidget);
    await tester.tap(find.byKey(const Key('recovery_ok')));
    await tester.pumpAndSettle(const Duration(seconds: 2));

    // Panel vacío
    expect(find.text('Aún no tienes movimientos'), findsOneWidget);

    // Agregar egreso
    await tester.tap(find.byKey(const Key('nav_add')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('tx_amount')), '45.90');
    await tester.tap(find.text('Alimentación'));
    await tester.enterText(find.byKey(const Key('tx_description')), 'Almuerzo');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.byKey(const Key('tx_save')), 300);
    await tester.tap(find.byKey(const Key('tx_save')));
    await tester.pumpAndSettle(const Duration(seconds: 2));

    // Panel con el movimiento y saldo negativo
    expect(find.text('Almuerzo'), findsWidgets);
    expect(find.text('-S/ 45.90'), findsWidgets);
  });
}
