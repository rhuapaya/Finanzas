// Pruebas de integración de los flujos principales sobre una base SQLite real
// (en memoria, vía sqflite_common_ffi): autenticación local, CRUD de
// movimientos, presupuestos con alertas, categorías con reasignación,
// recurrentes y copias de seguridad.
import 'package:finanzas_app/core/db/local_database.dart';
import 'package:finanzas_app/core/errors/app_exception.dart';
import 'package:finanzas_app/core/money/money.dart';
import 'package:finanzas_app/core/security/secure_store.dart';
import 'package:finanzas_app/core/services/notification_service.dart';
import 'package:finanzas_app/core/utils/dates.dart';
import 'package:finanzas_app/data/io/backup_service.dart';
import 'package:finanzas_app/data/models/app_user.dart';
import 'package:finanzas_app/data/models/category.dart';
import 'package:finanzas_app/data/models/enums.dart';
import 'package:finanzas_app/data/repositories/auth_repository.dart';
import 'package:finanzas_app/data/repositories/budget_repository.dart';
import 'package:finanzas_app/data/repositories/category_repository.dart';
import 'package:finanzas_app/data/repositories/data_change_bus.dart';
import 'package:finanzas_app/data/repositories/recurring_repository.dart';
import 'package:finanzas_app/data/repositories/transaction_repository.dart';
import 'package:finanzas_app/data/repositories/user_repository.dart';
import 'package:finanzas_app/data/seed/default_categories.dart';
import 'package:finanzas_app/data/seed/demo_data_service.dart';
import 'package:finanzas_app/data/services/budget_alert_service.dart';
import 'package:finanzas_app/data/services/recurring_service.dart';
import 'package:finanzas_app/data/services/transaction_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _Env {
  _Env(this.db) {
    bus = DataChangeBus();
    users = UserRepository(db, bus);
    categories = CategoryRepository(db, bus);
    transactions = TransactionRepository(db, bus);
    budgets = BudgetRepository(db, bus);
    recurringRepo = RecurringRepository(db, bus);
    notifier = SilentNotifier();
    alerts = BudgetAlertService(
      budgets: budgets,
      transactions: transactions,
      categories: categories,
      notifier: notifier,
    );
    txService = TransactionService(transactions, alerts);
    recurring = RecurringService(recurringRepo, txService, notifier);
    auth = LocalAuthRepository(users, InMemorySecureStore());
    backup = BackupService(
      local: db,
      bus: bus,
      categories: categories,
      transactions: transactions,
      budgets: budgets,
      recurring: recurringRepo,
    );
  }

  final LocalDatabase db;
  late final DataChangeBus bus;
  late final UserRepository users;
  late final CategoryRepository categories;
  late final TransactionRepository transactions;
  late final BudgetRepository budgets;
  late final RecurringRepository recurringRepo;
  late final SilentNotifier notifier;
  late final BudgetAlertService alerts;
  late final TransactionService txService;
  late final RecurringService recurring;
  late final LocalAuthRepository auth;
  late final BackupService backup;

  Future<AppUser> registerUser([String email = 'ana@correo.pe']) async {
    final result = await auth.signUp(email: email, password: 'clave2026', displayName: 'Ana');
    await categories.seedDefaults(result.user!.id);
    return result.user!;
  }

  Future<Category> category(String userId, String icon) async =>
      (await categories.getAll(userId)).firstWhere((c) => c.icon == icon);
}

void main() {
  late _Env env;

  setUpAll(sqfliteFfiInit);

  setUp(() async {
    final db = await LocalDatabase.open(factory: databaseFactoryFfi, path: inMemoryDatabasePath);
    env = _Env(db);
  });

  tearDown(() async {
    await env.db.close();
  });

  group('Autenticación local', () {
    test('registro, sesión persistente, cierre e inicio de sesión', () async {
      final result = await env.auth.signUp(email: 'Ana@Correo.pe ', password: 'clave2026', displayName: 'Ana');
      expect(result.user, isNotNull);
      expect(result.user!.email, 'ana@correo.pe');
      expect(result.recoveryCode, isNotNull);

      expect((await env.auth.restoreSession())?.id, result.user!.id);
      await env.auth.signOut();
      expect(await env.auth.restoreSession(), isNull);

      await expectLater(
        env.auth.signIn(email: 'ana@correo.pe', password: 'incorrecta1'),
        throwsA(isA<AuthFailure>()),
      );
      final user = await env.auth.signIn(email: 'ANA@correo.pe', password: 'clave2026');
      expect(user.id, result.user!.id);
    });

    test('no permite correos duplicados', () async {
      await env.registerUser();
      await expectLater(
        env.auth.signUp(email: 'ana@correo.pe', password: 'clave2026'),
        throwsA(isA<AuthFailure>()),
      );
    });

    test('recupera la contraseña con el código', () async {
      final result = await env.auth.signUp(email: 'luis@correo.pe', password: 'clave2026');
      await expectLater(
        env.auth.resetWithRecoveryCode(email: 'luis@correo.pe', recoveryCode: 'XXXX-XXXX', newPassword: 'nueva2027'),
        throwsA(isA<AuthFailure>()),
      );
      await env.auth.resetWithRecoveryCode(
        email: 'luis@correo.pe',
        recoveryCode: result.recoveryCode!.toLowerCase(),
        newPassword: 'nueva2027',
      );
      final user = await env.auth.signIn(email: 'luis@correo.pe', password: 'nueva2027');
      expect(user.email, 'luis@correo.pe');
    });

    test('preferencias por defecto: PEN y tema automático', () async {
      final user = await env.registerUser();
      expect(user.settings.currency, 'PEN');
      expect(user.settings.themeMode, AppThemeMode.system);
      final updated = await env.users.updateProfile(user, settings: user.settings.copyWith(currency: 'USD'));
      expect((await env.users.getById(user.id))!.settings.currency, 'USD');
      expect(updated.settings.currency, 'USD');
    });
  });

  group('Categorías', () {
    test('crea las categorías predeterminadas una sola vez', () async {
      final user = await env.registerUser();
      await env.categories.seedDefaults(user.id);
      final all = await env.categories.getAll(user.id);
      expect(all.length, DefaultCategories.all.length);
      expect(all.where((c) => c.type == TxType.income).map((c) => c.name),
          containsAll(['Salario', 'Ventas', 'Inversiones', 'Bonificaciones', 'Otros']));
      expect(all.where((c) => c.type == TxType.expense).length, 9);
    });

    test('crear, editar y validar nombres duplicados', () async {
      final user = await env.registerUser();
      final pets = await env.categories.create(
          userId: user.id, name: 'Mascotas', type: TxType.expense, color: 0xFF795548, icon: 'pets');
      await expectLater(
        env.categories.create(userId: user.id, name: ' mascotas ', type: TxType.expense, color: 1, icon: 'pets'),
        throwsA(isA<ValidationException>()),
      );
      // El mismo nombre sí se permite en el otro tipo.
      await env.categories.create(userId: user.id, name: 'Mascotas', type: TxType.income, color: 1, icon: 'pets');

      final edited = await env.categories.update(pets.copyWith(name: 'Mascotas y veterinaria', color: 0xFF000000));
      expect((await env.categories.getById(pets.id))!.name, 'Mascotas y veterinaria');
      expect(edited.color, 0xFF000000);
    });

    test('no elimina categorías con movimientos sin reasignar', () async {
      final user = await env.registerUser();
      final food = await env.category(user.id, 'food');
      final other = await env.category(user.id, 'other_expense');
      await env.txService.create(
        user,
        TransactionDraft(type: TxType.expense, amount: Money.parse('25'), categoryId: food.id, date: DateTime.now()),
      );
      expect(await env.categories.usageCount(food.id), 1);
      await expectLater(env.categories.delete(food.id), throwsA(isA<ValidationException>()));

      await env.categories.reassignAndDelete(food.id, other.id);
      final remaining = await env.categories.getAll(user.id);
      expect(remaining.any((c) => c.id == food.id), isFalse);
      final txs = await env.transactions.query(user.id, const TransactionFilter());
      expect(txs.single.categoryId, other.id);
    });

    test('elimina directamente una categoría sin uso', () async {
      final user = await env.registerUser();
      final edu = await env.category(user.id, 'education');
      await env.categories.delete(edu.id);
      expect((await env.categories.getAll(user.id)).any((c) => c.id == edu.id), isFalse);
    });
  });

  group('Movimientos', () {
    test('crear, consultar, editar, eliminar y calcular saldo', () async {
      final user = await env.registerUser();
      final salary = await env.category(user.id, 'salary');
      final food = await env.category(user.id, 'food');
      final today = Dates.today();

      await env.txService.create(
          user, TransactionDraft(type: TxType.income, amount: Money.parse('3000'), categoryId: salary.id, date: today));
      final lunch = await env.txService.create(
        user,
        TransactionDraft(
          type: TxType.expense,
          amount: Money.parse('45.90'),
          categoryId: food.id,
          date: today,
          description: '  Almuerzo  ',
          paymentMethod: PaymentMethod.digitalWallet,
        ),
      );
      expect(lunch.transaction.description, 'Almuerzo');
      expect(await env.transactions.balance(user.id), Money.parse('2954.10'));

      final filtered = await env.transactions.query(
          user.id, const TransactionFilter(type: TxType.expense, paymentMethod: PaymentMethod.digitalWallet));
      expect(filtered.single.id, lunch.transaction.id);
      final search = await env.transactions.query(user.id, const TransactionFilter(query: 'almu'));
      expect(search.length, 1);

      await env.txService.update(
        user,
        lunch.transaction,
        TransactionDraft(type: TxType.expense, amount: Money.parse('50'), categoryId: food.id, date: today),
      );
      expect(await env.transactions.balance(user.id), Money.parse('2950'));

      await env.txService.delete(user, (await env.transactions.getById(lunch.transaction.id))!);
      expect(await env.transactions.balance(user.id), Money.parse('3000'));
      expect(await env.transactions.countAll(user.id), 1);
    });

    test('rechaza montos menores o iguales a cero', () async {
      final user = await env.registerUser();
      final food = await env.category(user.id, 'food');
      for (final amount in ['0', '-10']) {
        await expectLater(
          env.txService.create(
            user,
            TransactionDraft(type: TxType.expense, amount: Money.parse(amount), categoryId: food.id, date: DateTime.now()),
          ),
          throwsA(isA<ValidationException>()),
        );
      }
    });

    test('los movimientos nuevos quedan pendientes de sincronizar', () async {
      final user = await env.registerUser();
      final food = await env.category(user.id, 'food');
      await env.txService.create(
          user, TransactionDraft(type: TxType.expense, amount: Money.parse('5'), categoryId: food.id, date: DateTime.now()));
      final rows = await env.db.db.query('transactions', columns: ['sync_status']);
      expect(rows.single['sync_status'], SyncStatus.pending);
    });
  });

  group('Presupuestos', () {
    test('alerta al 80 % y al 100 % una sola vez', () async {
      final user = await env.registerUser();
      final food = await env.category(user.id, 'food');
      final now = Dates.today();
      await env.budgets.create(
          userId: user.id, categoryId: food.id, limit: Money.parse('500'), year: now.year, month: now.month);

      Future<List<String>> spend(String amount) async => (await env.txService.create(
            user,
            TransactionDraft(type: TxType.expense, amount: Money.parse(amount), categoryId: food.id, date: now),
          ))
              .alerts;

      expect(await spend('300'), isEmpty);
      final at80 = await spend('100');
      expect(at80.single, contains('80 %'));
      expect(await spend('50'), isEmpty, reason: 'no repite la alerta de 80 %');
      final at100 = await spend('60');
      expect(at100.single, contains('agotado'));
      expect(await spend('10'), isEmpty, reason: 'no repite la alerta de 100 %');
      expect(env.notifier.sent.length, 2);

      final budget = await env.budgets.findByCategoryMonth(user.id, food.id, now.year, now.month);
      expect(budget!.alert80Sent, isTrue);
      expect(budget.alert100Sent, isTrue);
      expect(await env.transactions.sumForCategoryMonth(user.id, food.id, now.year, now.month), Money.parse('520'));
    });

    test('no permite dos presupuestos de la misma categoría en el mes', () async {
      final user = await env.registerUser();
      final food = await env.category(user.id, 'food');
      await env.budgets.create(userId: user.id, categoryId: food.id, limit: Money.parse('100'), year: 2026, month: 11);
      await expectLater(
        env.budgets.create(userId: user.id, categoryId: food.id, limit: Money.parse('200'), year: 2026, month: 11),
        throwsA(isA<ValidationException>()),
      );
    });

    test('respeta la preferencia de alertas desactivadas', () async {
      final base = await env.registerUser();
      final user = base.copyWith(settings: base.settings.copyWith(budgetAlertsEnabled: false));
      final food = await env.category(user.id, 'food');
      final now = Dates.today();
      await env.budgets.create(
          userId: user.id, categoryId: food.id, limit: Money.parse('10'), year: now.year, month: now.month);
      final result = await env.txService.create(
          user, TransactionDraft(type: TxType.expense, amount: Money.parse('20'), categoryId: food.id, date: now));
      expect(result.alerts, isEmpty);
      expect(env.notifier.sent, isEmpty);
    });
  });

  group('Recurrentes', () {
    test('genera los movimientos vencidos y avanza la próxima fecha', () async {
      final user = await env.registerUser();
      final home = await env.category(user.id, 'home');
      final today = DateTime(2026, 11, 7);
      final (rule, _) = await env.recurring.create(
        user,
        RecurringDraft(
          type: TxType.expense,
          amount: Money.parse('1200'),
          categoryId: home.id,
          frequency: Frequency.monthly,
          startDate: DateTime(2026, 9, 5),
          description: 'Alquiler',
        ),
        today: today,
      );
      expect(rule.nextDate, DateTime(2026, 12, 5));
      final txs = await env.transactions.query(user.id, const TransactionFilter());
      expect(txs.length, 3);
      expect(txs.every((t) => t.recurringId == rule.id), isTrue);

      // Procesar otra vez el mismo día no duplica.
      final (created, _) = await env.recurring.processDue(user, today: today);
      expect(created, 0);

      // Un mes después se agrega uno más.
      final (later, _) = await env.recurring.processDue(user, today: DateTime(2026, 12, 6));
      expect(later, 1);
    });

    test('pausado no genera y finaliza al pasar la fecha de fin', () async {
      final user = await env.registerUser();
      final salary = await env.category(user.id, 'salary');
      final (rule, _) = await env.recurring.create(
        user,
        RecurringDraft(
          type: TxType.income,
          amount: Money.parse('100'),
          categoryId: salary.id,
          frequency: Frequency.weekly,
          startDate: DateTime(2026, 12, 1),
          endDate: DateTime(2026, 12, 20),
        ),
        today: DateTime(2026, 11, 7),
      );
      final paused = await env.recurring.setStatus(rule, RecurringStatus.paused);
      expect((await env.recurring.processDue(user, today: DateTime(2026, 12, 31))).$1, 0);

      await env.recurring.setStatus(paused, RecurringStatus.active);
      expect((await env.recurring.processDue(user, today: DateTime(2026, 12, 31))).$1, 3);
      final finished = await env.recurringRepo.getById(rule.id);
      expect(finished!.status, RecurringStatus.finished);
    });
  });

  group('Datos de la cuenta', () {
    test('exportar e importar una copia de seguridad', () async {
      final user = await env.registerUser();
      final count = await DemoDataService(
        categories: env.categories,
        transactions: env.transactions,
        budgets: env.budgets,
        recurring: env.recurringRepo,
      ).generate(user, today: DateTime(2026, 11, 7));
      expect(count, greaterThan(50));
      final balanceBefore = await env.transactions.balance(user.id);

      final backup = await env.backup.buildBackup(user);
      await env.backup.deleteAllLocalData(user);
      expect(await env.transactions.countAll(user.id), 0);

      final summary = await env.backup.importData(user, backup);
      expect(summary.transactions, count);
      expect(await env.transactions.balance(user.id), balanceBefore);
    });

    test('rechaza archivos que no son copias válidas', () async {
      final user = await env.registerUser();
      await expectLater(env.backup.importData(user, {'foo': 1}), throwsA(isA<ValidationException>()));
    });

    test('cada usuario solo ve sus propios registros', () async {
      final ana = await env.registerUser('ana@correo.pe');
      final luis = await env.registerUser('luis@correo.pe');
      final food = await env.category(ana.id, 'food');
      await env.txService.create(
          ana, TransactionDraft(type: TxType.expense, amount: Money.parse('10'), categoryId: food.id, date: DateTime.now()));
      expect(await env.transactions.countAll(ana.id), 1);
      expect(await env.transactions.countAll(luis.id), 0);
      expect(await env.transactions.balance(luis.id), Money.zero);
    });
  });
}
