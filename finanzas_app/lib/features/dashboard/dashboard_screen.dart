import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/finance/finance_calculator.dart';
import '../../core/theme/app_theme.dart';
import '../../data/sync/sync_service.dart';
import '../../providers.dart';
import '../../shared/widgets/category_widgets.dart';
import '../../shared/widgets/money_widgets.dart';
import '../../shared/widgets/period_selector.dart';
import '../../shared/widgets/state_views.dart';
import '../../shared/widgets/transaction_tile.dart';
import 'expense_pie_chart.dart';

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _showPendingAlerts());
  }

  void _showPendingAlerts() {
    final session = ref.read(sessionServiceProvider);
    if (session.pendingAlerts.isEmpty || !mounted) return;
    final text = session.pendingAlerts.join('\n');
    session.pendingAlerts.clear();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text), showCloseIcon: true));
  }

  Future<void> _refresh() async {
    await ref.read(syncServiceProvider).syncNow();
    ref.read(dataRevisionProvider.notifier).state++;
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);
    final period = ref.watch(dashboardPeriodProvider);
    final data = ref.watch(dashboardDataProvider);
    final categories = ref.watch(categoryMapProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text('Hola, ${user?.greetingName ?? ''}'),
        actions: [
          if (user?.isRemote ?? false) const _SyncIndicator(),
          IconButton(
            tooltip: 'Presupuestos',
            icon: const Icon(Icons.savings_outlined),
            onPressed: () => context.push('/budgets'),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: data.when(
          loading: () => const LoadingView(message: 'Cargando tu resumen…'),
          error: (e, _) => ErrorView(error: e, onRetry: () => ref.invalidate(dashboardDataProvider)),
          data: (d) => ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              _BalanceCard(data: d, periodLabel: period.label),
              const SizedBox(height: 16),
              PeriodSelector(
                selection: period,
                onChanged: (p) => ref.read(dashboardPeriodProvider.notifier).state = p,
              ),
              const SizedBox(height: 8),
              _SummaryRow(summary: d.summary),
              if (d.budgetsAtRisk.isNotEmpty) ...[
                const SizedBox(height: 16),
                _BudgetAlertsCard(views: d.budgetsAtRisk),
              ],
              const SizedBox(height: 16),
              _Section(
                title: 'Gastos por categoría',
                child: d.expenseByCategory.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.symmetric(vertical: 24),
                        child: Text('No hay egresos en este periodo.', textAlign: TextAlign.center),
                      )
                    : ExpensePieChart(totals: d.expenseByCategory, categories: categories),
              ),
              const SizedBox(height: 16),
              _Section(
                title: 'Movimientos recientes',
                trailing: TextButton(
                  onPressed: () => context.go('/transactions'),
                  child: const Text('Ver todos'),
                ),
                child: d.recent.isEmpty
                    ? EmptyState(
                        icon: Icons.receipt_long_outlined,
                        title: 'Aún no tienes movimientos',
                        message: 'Registra tu primer ingreso o egreso para ver tu resumen.',
                        actionLabel: 'Agregar movimiento',
                        onAction: () => context.push('/transaction/new'),
                      )
                    : Column(children: [
                        for (final t in d.recent)
                          TransactionTile(
                            transaction: t,
                            category: categories[t.categoryId],
                            onTap: () => context.push('/transaction/${t.id}'),
                          ),
                      ]),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BalanceCard extends StatelessWidget {
  const _BalanceCard({required this.data, required this.periodLabel});

  final DashboardData data;
  final String periodLabel;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Card(
      elevation: 0,
      color: scheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Saldo actual', style: text.titleSmall?.copyWith(color: scheme.onPrimaryContainer)),
          const SizedBox(height: 6),
          Semantics(
            label: 'Saldo actual',
            child: AmountText(
              data.balance,
              key: const Key('balance_amount'),
              colored: data.balance.isNegative,
              style: text.headlineMedium?.copyWith(fontWeight: FontWeight.w700, color: scheme.onPrimaryContainer),
            ),
          ),
          const SizedBox(height: 4),
          Text('Ingresos menos egresos registrados',
              style: text.bodySmall?.copyWith(color: scheme.onPrimaryContainer.withAlpha(200))),
        ]),
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({required this.summary});

  final PeriodSummary summary;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget tile(String label, IconData icon, Color color, Widget value) => Expanded(
          child: Card(
            elevation: 0,
            color: scheme.surfaceContainerHigh,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Icon(icon, size: 18, color: color),
                  const SizedBox(width: 6),
                  Text(label, style: Theme.of(context).textTheme.labelLarge),
                ]),
                const SizedBox(height: 8),
                value,
              ]),
            ),
          ),
        );
    final valueStyle = Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700);
    return Column(children: [
      Row(children: [
        tile('Ingresos', Icons.arrow_downward, scheme.income,
            AmountText(summary.income, type: null, style: valueStyle?.copyWith(color: scheme.income))),
        const SizedBox(width: 8),
        tile('Egresos', Icons.arrow_upward, scheme.expense,
            AmountText(summary.expense, type: null, style: valueStyle?.copyWith(color: scheme.expense))),
      ]),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(children: [
          Text('Balance del periodo', style: Theme.of(context).textTheme.bodyMedium),
          const Spacer(),
          AmountText(summary.balance, showSign: true, style: valueStyle),
        ]),
      ),
    ]);
  }
}

class _BudgetAlertsCard extends StatelessWidget {
  const _BudgetAlertsCard({required this.views});

  final List<BudgetView> views;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      color: scheme.errorContainer.withAlpha(120),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.warning_amber_rounded, color: scheme.warning),
            const SizedBox(width: 8),
            Text('Presupuestos en alerta', style: Theme.of(context).textTheme.titleSmall),
            const Spacer(),
            TextButton(onPressed: () => context.push('/budgets'), child: const Text('Ver')),
          ]),
          for (final v in views)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(children: [
                CategoryAvatar(category: v.category, size: 30),
                const SizedBox(width: 10),
                Expanded(child: Text(v.category?.name ?? 'Categoría')),
                Text(
                  '${v.status.percent} %',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: v.status.level == BudgetLevel.exceeded ? scheme.expense : scheme.warning,
                  ),
                ),
              ]),
            ),
        ]),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child, this.trailing});

  final String title;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(child: Text(title, style: Theme.of(context).textTheme.titleMedium)),
            if (trailing != null) trailing!,
          ]),
          const SizedBox(height: 8),
          child,
        ]),
      ),
    );
  }
}

class _SyncIndicator extends ConsumerWidget {
  const _SyncIndicator();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sync = ref.watch(syncServiceProvider);
    return ValueListenableBuilder<SyncState>(
      valueListenable: sync.state,
      builder: (context, state, _) {
        final icon = switch (state.phase) {
          SyncPhase.syncing => Icons.sync,
          SyncPhase.success => Icons.cloud_done_outlined,
          SyncPhase.offline => Icons.cloud_off_outlined,
          SyncPhase.error => Icons.sync_problem,
          _ => Icons.cloud_queue,
        };
        return IconButton(
          tooltip: state.label,
          icon: Icon(icon),
          onPressed: () => sync.syncNow(),
        );
      },
    );
  }
}
