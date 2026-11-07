import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/finance/finance_calculator.dart';
import '../../core/money/money.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/dates.dart';
import '../../core/utils/validators.dart';
import '../../data/models/budget.dart';
import '../../data/models/category.dart';
import '../../data/models/enums.dart';
import '../../providers.dart';
import '../../shared/widgets/category_widgets.dart';
import '../../shared/widgets/feedback.dart';
import '../../shared/widgets/money_widgets.dart';
import '../../shared/widgets/state_views.dart';

class BudgetsScreen extends ConsumerWidget {
  const BudgetsScreen({super.key});

  Future<void> _openForm(BuildContext context, WidgetRef ref, DateTime month, List<BudgetView> existing,
      {BudgetView? edit}) async {
    final categories = (await ref.read(categoriesProvider.future)).where((c) => c.type == TxType.expense).toList();
    if (!context.mounted) return;
    final used = existing.map((v) => v.budget.categoryId).toSet();
    final available = edit != null
        ? categories
        : categories.where((c) => !used.contains(c.id)).toList();
    if (available.isEmpty) {
      showInfoSnack(context, 'Todas tus categorías de egresos ya tienen presupuesto este mes.');
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _BudgetForm(month: month, categories: available, edit: edit?.budget),
    );
  }

  Future<void> _delete(BuildContext context, WidgetRef ref, BudgetView v) async {
    final ok = await confirmAction(
      context,
      title: 'Eliminar presupuesto',
      message: '¿Eliminar el presupuesto de ${v.category?.name ?? 'esta categoría'}?',
    );
    if (!ok) return;
    try {
      await ref.read(budgetRepositoryProvider).softDelete(v.budget.id);
      if (context.mounted) showInfoSnack(context, 'Presupuesto eliminado');
    } catch (e) {
      if (context.mounted) showErrorSnack(context, e);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final month = ref.watch(budgetMonthProvider);
    final views = ref.watch(budgetViewsProvider(month));
    void shift(int delta) =>
        ref.read(budgetMonthProvider.notifier).state = DateTime(month.year, month.month + delta);

    return Scaffold(
      appBar: AppBar(title: const Text('Presupuestos')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openForm(context, ref, month, views.valueOrNull ?? const []),
        icon: const Icon(Icons.add),
        label: const Text('Nuevo'),
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(children: [
            IconButton(tooltip: 'Mes anterior', onPressed: () => shift(-1), icon: const Icon(Icons.chevron_left)),
            Expanded(
              child: Text(Dates.monthYear(month.year, month.month),
                  textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleMedium),
            ),
            IconButton(tooltip: 'Mes siguiente', onPressed: () => shift(1), icon: const Icon(Icons.chevron_right)),
          ]),
        ),
        Expanded(
          child: views.when(
            loading: () => const LoadingView(),
            error: (e, _) => ErrorView(error: e, onRetry: () => ref.invalidate(budgetViewsProvider(month))),
            data: (list) {
              if (list.isEmpty) {
                return EmptyState(
                  icon: Icons.savings_outlined,
                  title: 'Sin presupuestos este mes',
                  message: 'Define un límite mensual por categoría y te avisaremos al llegar al 80 % y al 100 %.',
                  actionLabel: 'Crear presupuesto',
                  onAction: () => _openForm(context, ref, month, list),
                );
              }
              final totalLimit = Money.sum(list.map((v) => v.budget.limit));
              final totalSpent = Money.sum(list.map((v) => v.status.spent));
              final total = BudgetStatus(limit: totalLimit, spent: totalSpent);
              return ListView(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
                children: [
                  _TotalCard(status: total),
                  const SizedBox(height: 8),
                  for (final v in list)
                    _BudgetCard(
                      view: v,
                      onEdit: () => _openForm(context, ref, month, list, edit: v),
                      onDelete: () => _delete(context, ref, v),
                    ),
                ],
              );
            },
          ),
        ),
      ]),
    );
  }
}

Color _levelColor(ColorScheme scheme, BudgetLevel level) => switch (level) {
      BudgetLevel.ok => scheme.income,
      BudgetLevel.warning => scheme.warning,
      BudgetLevel.exceeded => scheme.expense,
    };

class _TotalCard extends StatelessWidget {
  const _TotalCard({required this.status});

  final BudgetStatus status;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Card(
      elevation: 0,
      color: scheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Total del mes', style: text.titleSmall),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: AmountText(status.spent, colored: false, style: text.titleLarge)),
            Text('de ', style: text.bodyMedium),
            AmountText(status.limit, colored: false, style: text.bodyLarge),
          ]),
          const SizedBox(height: 8),
          LinearProgressIndicator(
            value: status.progress,
            minHeight: 10,
            borderRadius: BorderRadius.circular(8),
            color: _levelColor(scheme, status.level),
            backgroundColor: scheme.surface,
          ),
        ]),
      ),
    );
  }
}

class _BudgetCard extends StatelessWidget {
  const _BudgetCard({required this.view, required this.onEdit, required this.onDelete});

  final BudgetView view;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final s = view.status;
    final color = _levelColor(scheme, s.level);
    return Card(
      elevation: 0,
      color: scheme.surfaceContainerLow,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onEdit,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 4, 14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              CategoryAvatar(category: view.category, size: 38),
              const SizedBox(width: 12),
              Expanded(child: Text(view.category?.name ?? 'Categoría eliminada', style: text.titleMedium)),
              Text('${s.percent} %', style: text.titleSmall?.copyWith(color: color, fontWeight: FontWeight.bold)),
              PopupMenuButton<String>(
                tooltip: 'Opciones',
                onSelected: (v) => v == 'edit' ? onEdit() : onDelete(),
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'edit', child: Text('Editar')),
                  PopupMenuItem(value: 'delete', child: Text('Eliminar')),
                ],
              ),
            ]),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Semantics(
                label: 'Consumido ${s.percent} por ciento',
                child: LinearProgressIndicator(
                  value: s.progress,
                  minHeight: 10,
                  borderRadius: BorderRadius.circular(8),
                  color: color,
                  backgroundColor: scheme.surfaceContainerHighest,
                ),
              ),
            ),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Consumido', style: text.bodySmall),
                    AmountText(s.spent, colored: false, style: text.bodyMedium),
                  ]),
                ),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.center, children: [
                    Text('Límite', style: text.bodySmall),
                    AmountText(view.budget.limit, colored: false, style: text.bodyMedium),
                  ]),
                ),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    Text(s.available.isNegative ? 'Excedido' : 'Disponible', style: text.bodySmall),
                    AmountText(s.available.abs(),
                        colored: false, style: text.bodyMedium?.copyWith(color: color, fontWeight: FontWeight.w600)),
                  ]),
                ),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

class _BudgetForm extends ConsumerStatefulWidget {
  const _BudgetForm({required this.month, required this.categories, this.edit});

  final DateTime month;
  final List<Category> categories;
  final Budget? edit;

  @override
  ConsumerState<_BudgetForm> createState() => _BudgetFormState();
}

class _BudgetFormState extends ConsumerState<_BudgetForm> {
  final _formKey = GlobalKey<FormState>();
  late final _amount = TextEditingController(text: widget.edit?.limit.toDecimalString() ?? '');
  late String? _categoryId = widget.edit?.categoryId;
  bool _saving = false;

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_categoryId == null) {
      showInfoSnack(context, 'Selecciona una categoría.');
      return;
    }
    final user = ref.read(currentUserProvider);
    if (user == null) return;
    setState(() => _saving = true);
    final repo = ref.read(budgetRepositoryProvider);
    try {
      final limit = Money.parse(_amount.text);
      if (widget.edit != null) {
        await repo.update(widget.edit!.copyWith(limit: limit, categoryId: _categoryId));
      } else {
        await repo.create(
          userId: user.id,
          categoryId: _categoryId!,
          limit: limit,
          year: widget.month.year,
          month: widget.month.month,
        );
      }
      // Recalcula las alertas con el nuevo límite.
      final alerts = await ref.read(budgetAlertServiceProvider).evaluate(
            user: user,
            categoryId: _categoryId!,
            date: DateTime(widget.month.year, widget.month.month, 1),
          );
      if (!mounted) return;
      Navigator.pop(context);
      showInfoSnack(context, alerts.isEmpty ? 'Presupuesto guardado' : 'Presupuesto guardado\n${alerts.join('\n')}');
    } catch (e) {
      if (mounted) showErrorSnack(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(widget.edit == null ? 'Nuevo presupuesto' : 'Editar presupuesto',
                  style: Theme.of(context).textTheme.titleLarge),
              Text(Dates.monthYear(widget.month.year, widget.month.month),
                  style: Theme.of(context).textTheme.bodyMedium),
              const SizedBox(height: 16),
              Text('Categoría de egresos', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              CategoryPicker(
                categories: widget.categories,
                selectedId: _categoryId,
                onSelected: (c) => setState(() => _categoryId = c.id),
              ),
              const SizedBox(height: 16),
              AmountField(controller: _amount, label: 'Límite mensual', validator: Validators.amount),
              const SizedBox(height: 20),
              FilledButton(onPressed: _saving ? null : _save, child: const Text('Guardar')),
            ]),
          ),
        ),
      ),
    );
  }
}
