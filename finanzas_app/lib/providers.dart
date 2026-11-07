import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show Supabase, SupabaseClient;

import 'core/config/app_config.dart';
import 'core/db/local_database.dart';
import 'core/finance/finance_calculator.dart';
import 'core/money/currency.dart';
import 'core/money/money.dart';
import 'core/security/secure_store.dart';
import 'core/services/biometric_service.dart';
import 'core/services/connectivity_service.dart';
import 'core/services/notification_service.dart';
import 'core/utils/date_range.dart';
import 'core/utils/dates.dart';
import 'data/io/backup_service.dart';
import 'data/io/export_service.dart';
import 'data/models/app_user.dart';
import 'data/models/budget.dart';
import 'data/models/category.dart';
import 'data/models/enums.dart';
import 'data/models/fin_transaction.dart';
import 'data/models/recurring_transaction.dart';
import 'data/repositories/auth_repository.dart';
import 'data/repositories/budget_repository.dart';
import 'data/repositories/category_repository.dart';
import 'data/repositories/data_change_bus.dart';
import 'data/repositories/recurring_repository.dart';
import 'data/repositories/transaction_repository.dart';
import 'data/repositories/user_repository.dart';
import 'data/seed/demo_data_service.dart';
import 'data/services/budget_alert_service.dart';
import 'data/services/recurring_service.dart';
import 'data/services/session_service.dart';
import 'data/services/transaction_service.dart';
import 'data/sync/sync_service.dart';
import 'features/auth/auth_controller.dart';

// ---------------------------------------------------------------------------
// Infraestructura (sobrescritos en main.dart / pruebas)
// ---------------------------------------------------------------------------

final localDatabaseProvider = Provider<LocalDatabase>((ref) => throw UnimplementedError());
final sharedPreferencesProvider = Provider<SharedPreferences>((ref) => throw UnimplementedError());
final appConfigProvider = Provider<AppConfig>((ref) => const AppConfig());
final secureStoreProvider = Provider<SecureStore>((ref) => const FlutterSecureStore());
final alertNotifierProvider = Provider<AlertNotifier>((ref) => NotificationService.instance);
final biometricServiceProvider = Provider<BiometricService>((ref) => BiometricService());
final connectivityServiceProvider = Provider<ConnectivityService>((ref) => ConnectivityService());

final supabaseClientProvider = Provider<SupabaseClient?>((ref) {
  final config = ref.watch(appConfigProvider);
  return config.supabaseReady ? Supabase.instance.client : null;
});

final dataChangeBusProvider = Provider<DataChangeBus>((ref) {
  final bus = DataChangeBus();
  ref.onDispose(bus.dispose);
  return bus;
});

/// Se incrementa con cada cambio de datos para refrescar las vistas.
final dataRevisionProvider = StateProvider<int>((ref) => 0);

// ---------------------------------------------------------------------------
// Repositorios y servicios
// ---------------------------------------------------------------------------

final userRepositoryProvider = Provider(
    (ref) => UserRepository(ref.watch(localDatabaseProvider), ref.watch(dataChangeBusProvider)));
final categoryRepositoryProvider = Provider(
    (ref) => CategoryRepository(ref.watch(localDatabaseProvider), ref.watch(dataChangeBusProvider)));
final transactionRepositoryProvider = Provider(
    (ref) => TransactionRepository(ref.watch(localDatabaseProvider), ref.watch(dataChangeBusProvider)));
final budgetRepositoryProvider = Provider(
    (ref) => BudgetRepository(ref.watch(localDatabaseProvider), ref.watch(dataChangeBusProvider)));
final recurringRepositoryProvider = Provider(
    (ref) => RecurringRepository(ref.watch(localDatabaseProvider), ref.watch(dataChangeBusProvider)));

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  final client = ref.watch(supabaseClientProvider);
  final users = ref.watch(userRepositoryProvider);
  if (client != null) return SupabaseAuthRepository(client, users);
  return LocalAuthRepository(users, ref.watch(secureStoreProvider));
});

final budgetAlertServiceProvider = Provider((ref) => BudgetAlertService(
      budgets: ref.watch(budgetRepositoryProvider),
      transactions: ref.watch(transactionRepositoryProvider),
      categories: ref.watch(categoryRepositoryProvider),
      notifier: ref.watch(alertNotifierProvider),
    ));

final transactionServiceProvider = Provider(
    (ref) => TransactionService(ref.watch(transactionRepositoryProvider), ref.watch(budgetAlertServiceProvider)));

final recurringServiceProvider = Provider((ref) => RecurringService(
      ref.watch(recurringRepositoryProvider),
      ref.watch(transactionServiceProvider),
      ref.watch(alertNotifierProvider),
    ));

final syncServiceProvider = Provider<SyncService>((ref) {
  final service = SyncService(
    local: ref.watch(localDatabaseProvider),
    bus: ref.watch(dataChangeBusProvider),
    users: ref.watch(userRepositoryProvider),
    connectivity: ref.watch(connectivityServiceProvider),
    client: ref.watch(supabaseClientProvider),
  );
  ref.onDispose(service.dispose);
  return service;
});

final sessionServiceProvider = Provider((ref) => SessionService(
      categories: ref.watch(categoryRepositoryProvider),
      recurring: ref.watch(recurringServiceProvider),
      sync: ref.watch(syncServiceProvider),
    ));

final exportServiceProvider = Provider((ref) => const ExportService());

final backupServiceProvider = Provider((ref) => BackupService(
      local: ref.watch(localDatabaseProvider),
      bus: ref.watch(dataChangeBusProvider),
      categories: ref.watch(categoryRepositoryProvider),
      transactions: ref.watch(transactionRepositoryProvider),
      budgets: ref.watch(budgetRepositoryProvider),
      recurring: ref.watch(recurringRepositoryProvider),
    ));

final demoDataServiceProvider = Provider((ref) => DemoDataService(
      categories: ref.watch(categoryRepositoryProvider),
      transactions: ref.watch(transactionRepositoryProvider),
      budgets: ref.watch(budgetRepositoryProvider),
      recurring: ref.watch(recurringRepositoryProvider),
    ));

final authControllerProvider = ChangeNotifierProvider<AuthController>((ref) {
  final session = ref.watch(sessionServiceProvider);
  return AuthController(
    repository: ref.watch(authRepositoryProvider),
    users: ref.watch(userRepositoryProvider),
    biometric: ref.watch(biometricServiceProvider),
    hooks: SessionHooks(onSignedIn: session.onSignedIn, onSignedOut: session.onSignedOut),
  );
});

// ---------------------------------------------------------------------------
// Sesión y preferencias
// ---------------------------------------------------------------------------

final currentUserProvider = Provider<AppUser?>((ref) => ref.watch(authControllerProvider).user);

final currentUserIdProvider = Provider<String?>((ref) => ref.watch(currentUserProvider)?.id);

final settingsProvider =
    Provider<UserSettings>((ref) => ref.watch(currentUserProvider)?.settings ?? const UserSettings());

final currencyProvider =
    Provider<CurrencyInfo>((ref) => CurrencyInfo.byCode(ref.watch(settingsProvider).currency));

// ---------------------------------------------------------------------------
// Categorías
// ---------------------------------------------------------------------------

final categoriesProvider = FutureProvider<List<Category>>((ref) async {
  ref.watch(dataRevisionProvider);
  final uid = ref.watch(currentUserIdProvider);
  if (uid == null) return const [];
  return ref.watch(categoryRepositoryProvider).getAll(uid);
});

final categoryMapProvider = Provider<Map<String, Category>>((ref) {
  final list = ref.watch(categoriesProvider).valueOrNull ?? const <Category>[];
  return {for (final c in list) c.id: c};
});

// ---------------------------------------------------------------------------
// Panel principal
// ---------------------------------------------------------------------------

class DashboardData {
  const DashboardData({
    required this.balance,
    required this.summary,
    required this.expenseByCategory,
    required this.recent,
    required this.budgetsAtRisk,
  });

  final Money balance;
  final PeriodSummary summary;
  final List<CategoryTotal> expenseByCategory;
  final List<FinTransaction> recent;
  final List<BudgetView> budgetsAtRisk;

  bool get isEmpty => recent.isEmpty;
}

final dashboardPeriodProvider =
    StateProvider<PeriodSelection>((ref) => PeriodSelection.current(PeriodType.month));

final dashboardDataProvider = FutureProvider.autoDispose<DashboardData>((ref) async {
  ref.watch(dataRevisionProvider);
  final uid = ref.watch(currentUserIdProvider);
  final period = ref.watch(dashboardPeriodProvider);
  if (uid == null) {
    return const DashboardData(
      balance: Money.zero,
      summary: PeriodSummary.empty,
      expenseByCategory: [],
      recent: [],
      budgetsAtRisk: [],
    );
  }
  final repo = ref.watch(transactionRepositoryProvider);
  final txs = await repo.query(uid, TransactionFilter(range: period.range));
  final today = Dates.today();
  final budgets = await ref.watch(budgetViewsProvider(DateTime(today.year, today.month)).future);
  return DashboardData(
    balance: await repo.balance(uid),
    summary: FinanceCalculator.summarize(txs),
    expenseByCategory: FinanceCalculator.totalsByCategory(txs, TxType.expense),
    recent: await repo.recent(uid, limit: 6),
    budgetsAtRisk: budgets.where((b) => b.status.level != BudgetLevel.ok).toList(),
  );
});

// ---------------------------------------------------------------------------
// Movimientos
// ---------------------------------------------------------------------------

final transactionsPeriodProvider =
    StateProvider<PeriodSelection>((ref) => PeriodSelection.current(PeriodType.month));

final transactionsFilterProvider = StateProvider<TransactionFilter>((ref) => const TransactionFilter());

final filteredTransactionsProvider = FutureProvider.autoDispose<List<FinTransaction>>((ref) async {
  ref.watch(dataRevisionProvider);
  final uid = ref.watch(currentUserIdProvider);
  if (uid == null) return const [];
  final period = ref.watch(transactionsPeriodProvider);
  final filter = ref.watch(transactionsFilterProvider).copyWith(range: period.range);
  return ref.watch(transactionRepositoryProvider).query(uid, filter);
});

// ---------------------------------------------------------------------------
// Presupuestos
// ---------------------------------------------------------------------------

class BudgetView {
  const BudgetView({required this.budget, required this.category, required this.status});

  final Budget budget;
  final Category? category;
  final BudgetStatus status;
}

final budgetMonthProvider = StateProvider<DateTime>((ref) {
  final t = Dates.today();
  return DateTime(t.year, t.month);
});

/// Presupuestos de un mes con su consumo.
final budgetViewsProvider = FutureProvider.autoDispose.family<List<BudgetView>, DateTime>((ref, month) async {
  ref.watch(dataRevisionProvider);
  final uid = ref.watch(currentUserIdProvider);
  if (uid == null) return const [];
  final budgets = await ref.watch(budgetRepositoryProvider).forMonth(uid, month.year, month.month);
  final spent =
      await ref.watch(transactionRepositoryProvider).expensesByCategoryForMonth(uid, month.year, month.month);
  final categories = await ref.watch(categoriesProvider.future);
  final byId = {for (final c in categories) c.id: c};
  final views = budgets
      .map((b) => BudgetView(
            budget: b,
            category: byId[b.categoryId],
            status: BudgetStatus(limit: b.limit, spent: spent[b.categoryId] ?? Money.zero),
          ))
      .toList()
    ..sort((a, b) => b.status.percent.compareTo(a.status.percent));
  return views;
});

// ---------------------------------------------------------------------------
// Recurrentes
// ---------------------------------------------------------------------------

final recurringListProvider = FutureProvider.autoDispose<List<RecurringTransaction>>((ref) async {
  ref.watch(dataRevisionProvider);
  final uid = ref.watch(currentUserIdProvider);
  if (uid == null) return const [];
  return ref.watch(recurringRepositoryProvider).getAll(uid);
});

// ---------------------------------------------------------------------------
// Reportes
// ---------------------------------------------------------------------------

class ReportsData {
  const ReportsData({
    required this.transactions,
    required this.summary,
    required this.previousSummary,
    required this.monthly,
    required this.expenseByCategory,
    required this.incomeByCategory,
  });

  final List<FinTransaction> transactions;
  final PeriodSummary summary;
  final PeriodSummary previousSummary;
  final List<MonthlyTotal> monthly;
  final List<CategoryTotal> expenseByCategory;
  final List<CategoryTotal> incomeByCategory;
}

final reportsPeriodProvider =
    StateProvider<PeriodSelection>((ref) => PeriodSelection.current(PeriodType.month));

final reportsFilterProvider = StateProvider<TransactionFilter>((ref) => const TransactionFilter());

final reportsDataProvider = FutureProvider.autoDispose<ReportsData>((ref) async {
  ref.watch(dataRevisionProvider);
  final uid = ref.watch(currentUserIdProvider);
  final period = ref.watch(reportsPeriodProvider);
  final base = ref.watch(reportsFilterProvider);
  final repo = ref.watch(transactionRepositoryProvider);
  if (uid == null) {
    return const ReportsData(
      transactions: [],
      summary: PeriodSummary.empty,
      previousSummary: PeriodSummary.empty,
      monthly: [],
      expenseByCategory: [],
      incomeByCategory: [],
    );
  }
  final txs = await repo.query(uid, base.copyWith(range: period.range));
  final previous = await repo.query(uid, base.copyWith(range: period.range.previous(period.type)));

  final end = period.range.end;
  final trendRange = DateRange(DateTime(end.year, end.month - 11, 1), DateTime(end.year, end.month + 1, 0));
  final trendTxs = await repo.query(uid, base.copyWith(range: trendRange));

  return ReportsData(
    transactions: txs,
    summary: FinanceCalculator.summarize(txs),
    previousSummary: FinanceCalculator.summarize(previous),
    monthly: FinanceCalculator.monthlyTotals(trendTxs, endMonth: end, months: 12),
    expenseByCategory: FinanceCalculator.totalsByCategory(txs, TxType.expense),
    incomeByCategory: FinanceCalculator.totalsByCategory(txs, TxType.income),
  );
});
