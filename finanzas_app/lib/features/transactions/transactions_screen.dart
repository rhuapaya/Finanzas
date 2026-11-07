import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/finance/finance_calculator.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/dates.dart';
import '../../data/models/fin_transaction.dart';
import '../../data/repositories/transaction_repository.dart';
import '../../providers.dart';
import '../../shared/widgets/feedback.dart';
import '../../shared/widgets/money_widgets.dart';
import '../../shared/widgets/period_selector.dart';
import '../../shared/widgets/state_views.dart';
import '../../shared/widgets/transaction_tile.dart';
import 'filter_sheet.dart';

class TransactionsScreen extends ConsumerStatefulWidget {
  const TransactionsScreen({super.key});

  @override
  ConsumerState<TransactionsScreen> createState() => _TransactionsScreenState();
}

class _TransactionsScreenState extends ConsumerState<TransactionsScreen> {
  bool _searching = false;
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _setFilter(TransactionFilter filter) => ref.read(transactionsFilterProvider.notifier).state = filter;

  Future<bool> _confirmDelete(FinTransaction t) async {
    final ok = await confirmAction(
      context,
      title: 'Eliminar movimiento',
      message: '¿Seguro que deseas eliminar este movimiento? Esta acción no se puede deshacer.',
    );
    if (!ok) return false;
    final user = ref.read(currentUserProvider);
    if (user == null) return false;
    try {
      await ref.read(transactionServiceProvider).delete(user, t);
      if (mounted) showInfoSnack(context, 'Movimiento eliminado');
      return true;
    } catch (e) {
      if (mounted) showErrorSnack(context, e);
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final period = ref.watch(transactionsPeriodProvider);
    final filter = ref.watch(transactionsFilterProvider);
    final txs = ref.watch(filteredTransactionsProvider);
    final categories = ref.watch(categoryMapProvider);

    return Scaffold(
      appBar: AppBar(
        title: _searching
            ? TextField(
                controller: _search,
                autofocus: true,
                textInputAction: TextInputAction.search,
                decoration: const InputDecoration(
                  hintText: 'Buscar por descripción',
                  border: InputBorder.none,
                  filled: false,
                ),
                onChanged: (q) => _setFilter(filter.copyWith(query: q)),
              )
            : const Text('Movimientos'),
        actions: [
          IconButton(
            tooltip: _searching ? 'Cerrar búsqueda' : 'Buscar',
            icon: Icon(_searching ? Icons.close : Icons.search),
            onPressed: () {
              setState(() => _searching = !_searching);
              if (!_searching) {
                _search.clear();
                _setFilter(filter.copyWith(query: ''));
              }
            },
          ),
          IconButton(
            tooltip: 'Filtros',
            icon: Badge(
              isLabelVisible: filter.type != null || filter.categoryId != null || filter.paymentMethod != null,
              child: const Icon(Icons.filter_list),
            ),
            onPressed: () async {
              final result = await showTransactionFilterSheet(context, filter);
              if (result != null) _setFilter(result);
            },
          ),
        ],
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: PeriodSelector(
            selection: period,
            onChanged: (p) => ref.read(transactionsPeriodProvider.notifier).state = p,
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: ActiveFilterChips(filter: filter, onChanged: _setFilter),
        ),
        Expanded(
          child: txs.when(
            loading: () => const LoadingView(),
            error: (e, _) => ErrorView(error: e, onRetry: () => ref.invalidate(filteredTransactionsProvider)),
            data: (list) {
              if (list.isEmpty) {
                return EmptyState(
                  icon: Icons.search_off,
                  title: 'No hay movimientos',
                  message: filter.hasExtraFilters
                      ? 'No encontramos movimientos con estos filtros en el periodo seleccionado.'
                      : 'No registraste movimientos en este periodo.',
                  actionLabel: 'Agregar movimiento',
                  onAction: () => context.push('/transaction/new'),
                );
              }
              final summary = FinanceCalculator.summarize(list);
              final groups = <DateTime, List<FinTransaction>>{};
              for (final t in list) {
                groups.putIfAbsent(Dates.dateOnly(t.date), () => []).add(t);
              }
              final scheme = Theme.of(context).colorScheme;
              return ListView(
                padding: const EdgeInsets.only(bottom: 24),
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    child: Wrap(spacing: 16, runSpacing: 4, children: [
                      Text('${list.length} movimientos', style: Theme.of(context).textTheme.bodySmall),
                      AmountText(summary.income, type: null, colored: false,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.income)),
                      AmountText(-summary.expense, colored: false,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.expense)),
                    ]),
                  ),
                  for (final entry in groups.entries) ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                      child: Text(
                        Dates.formatDayHeader(entry.key),
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(color: scheme.primary),
                      ),
                    ),
                    for (final t in entry.value)
                      Dismissible(
                        key: ValueKey(t.id),
                        direction: DismissDirection.endToStart,
                        confirmDismiss: (_) => _confirmDelete(t),
                        background: Container(
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          color: scheme.errorContainer,
                          child: Icon(Icons.delete_outline, color: scheme.onErrorContainer),
                        ),
                        child: TransactionTile(
                          transaction: t,
                          category: categories[t.categoryId],
                          showDate: false,
                          onTap: () => context.push('/transaction/${t.id}'),
                        ),
                      ),
                  ],
                ],
              );
            },
          ),
        ),
      ]),
    );
  }
}
