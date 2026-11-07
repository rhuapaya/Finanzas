import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/finance/finance_calculator.dart';
import '../../core/money/money.dart';
import '../../core/theme/app_theme.dart';
import '../../data/io/export_service.dart';
import '../../data/models/category.dart';
import '../../providers.dart';
import '../../shared/widgets/category_widgets.dart';
import '../../shared/widgets/feedback.dart';
import '../../shared/widgets/money_widgets.dart';
import '../../shared/widgets/period_selector.dart';
import '../../shared/widgets/state_views.dart';
import '../transactions/filter_sheet.dart';
import 'report_charts.dart';

class ReportsScreen extends ConsumerWidget {
  const ReportsScreen({super.key});

  Future<void> _export(BuildContext context, WidgetRef ref, String format) async {
    final data = ref.read(reportsDataProvider).valueOrNull;
    if (data == null || data.transactions.isEmpty) {
      showInfoSnack(context, 'No hay movimientos para exportar en este periodo.');
      return;
    }
    final period = ref.read(reportsPeriodProvider);
    final filter = ref.read(reportsFilterProvider);
    final categories = ref.read(categoryMapProvider);
    final service = ref.read(exportServiceProvider);
    final export = ReportExport(
      title: 'Reporte de finanzas',
      periodLabel: period.label,
      transactions: data.transactions,
      categories: categories,
      currency: ref.read(currencyProvider),
      filtersDescription: describeFilter(filter, {for (final c in categories.values) c.id: c.name}),
    );
    try {
      final file = await runWithProgress(
        context,
        () => format == 'pdf' ? service.buildPdf(export) : service.buildCsv(export),
        message: 'Generando ${format.toUpperCase()}…',
      );
      if (file != null) await service.share(file);
    } catch (e) {
      if (context.mounted) showErrorSnack(context, e);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final period = ref.watch(reportsPeriodProvider);
    final filter = ref.watch(reportsFilterProvider);
    final data = ref.watch(reportsDataProvider);
    final categories = ref.watch(categoryMapProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Reportes'),
        actions: [
          IconButton(
            tooltip: 'Filtros',
            icon: Badge(isLabelVisible: filter.hasExtraFilters, child: const Icon(Icons.filter_list)),
            onPressed: () async {
              final result = await showTransactionFilterSheet(context, filter);
              if (result != null) ref.read(reportsFilterProvider.notifier).state = result;
            },
          ),
          PopupMenuButton<String>(
            tooltip: 'Exportar',
            icon: const Icon(Icons.ios_share),
            onSelected: (f) => _export(context, ref, f),
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: 'csv',
                child: ListTile(leading: Icon(Icons.table_chart_outlined), title: Text('Exportar CSV')),
              ),
              PopupMenuItem(
                value: 'pdf',
                child: ListTile(leading: Icon(Icons.picture_as_pdf_outlined), title: Text('Exportar PDF')),
              ),
            ],
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          PeriodSelector(
            selection: period,
            onChanged: (p) => ref.read(reportsPeriodProvider.notifier).state = p,
          ),
          ActiveFilterChips(
            filter: filter,
            onChanged: (f) => ref.read(reportsFilterProvider.notifier).state = f,
          ),
          const SizedBox(height: 8),
          data.when(
            loading: () => const Padding(padding: EdgeInsets.all(48), child: LoadingView()),
            error: (e, _) => ErrorView(error: e, onRetry: () => ref.invalidate(reportsDataProvider)),
            data: (d) {
              final hasTrend = d.monthly.any((m) => !m.income.isZero || !m.expense.isZero);
              if (d.transactions.isEmpty && !hasTrend) {
                return const EmptyState(
                  icon: Icons.insights_outlined,
                  title: 'Sin datos para reportar',
                  message: 'No hay movimientos en el periodo y filtros seleccionados.',
                );
              }
              return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                _ComparisonCard(current: d.summary, previous: d.previousSummary),
                const SizedBox(height: 12),
                _ReportCard(
                  title: 'Ingresos vs egresos (últimos 6 meses)',
                  child: IncomeExpenseBarChart(
                    months: d.monthly.length > 6 ? d.monthly.sublist(d.monthly.length - 6) : d.monthly,
                  ),
                ),
                const SizedBox(height: 12),
                _ReportCard(
                  title: 'Tendencia mensual (12 meses)',
                  child: MonthlyTrendChart(months: d.monthly),
                ),
                const SizedBox(height: 12),
                _CategoryBreakdown(
                  title: 'Egresos por categoría',
                  totals: d.expenseByCategory,
                  categories: categories,
                ),
                const SizedBox(height: 12),
                _CategoryBreakdown(
                  title: 'Ingresos por categoría',
                  totals: d.incomeByCategory,
                  categories: categories,
                ),
              ]);
            },
          ),
        ],
      ),
    );
  }
}

class _ReportCard extends StatelessWidget {
  const _ReportCard({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          child,
        ]),
      ),
    );
  }
}

class _ComparisonCard extends StatelessWidget {
  const _ComparisonCard({required this.current, required this.previous});

  final PeriodSummary current;
  final PeriodSummary previous;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    Widget row(String label, Money now, Money before, Color color, {bool higherIsBetter = true}) {
      final change = FinanceCalculator.percentChange(before, now);
      final improved = change == null ? null : (higherIsBetter ? change >= 0 : change <= 0);
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(children: [
          Expanded(child: Text(label, style: text.bodyLarge)),
          AmountText(now, colored: false, style: text.titleMedium?.copyWith(color: color, fontWeight: FontWeight.w600)),
          const SizedBox(width: 8),
          SizedBox(
            width: 72,
            child: change == null
                ? Text('—', textAlign: TextAlign.end, style: text.bodySmall)
                : Text(
                    '${change > 0 ? '▲' : change < 0 ? '▼' : ''} ${change.abs()} %',
                    textAlign: TextAlign.end,
                    style: text.bodySmall?.copyWith(
                      color: improved! ? scheme.income : scheme.expense,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
          ),
        ]),
      );
    }

    return _ReportCard(
      title: 'Resumen y comparación con el periodo anterior',
      child: Column(children: [
        row('Ingresos', current.income, previous.income, scheme.income),
        row('Egresos', current.expense, previous.expense, scheme.expense, higherIsBetter: false),
        const Divider(),
        row('Balance', current.balance, previous.balance,
            current.balance.isNegative ? scheme.expense : scheme.onSurface),
        Align(
          alignment: Alignment.centerLeft,
          child: Text(
            current.income.isZero
                ? '${current.count} movimientos'
                : '${current.count} movimientos · Ahorro: ${current.savingsRate} % de los ingresos',
            style: text.bodySmall,
          ),
        ),
      ]),
    );
  }
}

class _CategoryBreakdown extends StatelessWidget {
  const _CategoryBreakdown({required this.title, required this.totals, required this.categories});

  final String title;
  final List<CategoryTotal> totals;
  final Map<String, Category> categories;

  @override
  Widget build(BuildContext context) {
    if (totals.isEmpty) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    return _ReportCard(
      title: title,
      child: Column(children: [
        for (final t in totals)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(children: [
              CategoryAvatar(category: categories[t.categoryId], size: 34),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(
                      child: Text(categories[t.categoryId]?.name ?? 'Sin categoría',
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                    ),
                    AmountText(t.total, colored: false, style: Theme.of(context).textTheme.bodyMedium),
                  ]),
                  const SizedBox(height: 4),
                  LinearProgressIndicator(
                    value: t.percent / 100,
                    minHeight: 6,
                    borderRadius: BorderRadius.circular(6),
                    color: categories[t.categoryId] == null
                        ? scheme.outline
                        : Color(categories[t.categoryId]!.color),
                    backgroundColor: scheme.surfaceContainerHighest,
                  ),
                  const SizedBox(height: 2),
                  Text('${t.percent} % · ${t.count} movimientos', style: Theme.of(context).textTheme.bodySmall),
                ]),
              ),
            ]),
          ),
      ]),
    );
  }
}
