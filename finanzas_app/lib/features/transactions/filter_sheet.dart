import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/enums.dart';
import '../../data/repositories/transaction_repository.dart';
import '../../providers.dart';
import '../../shared/widgets/category_widgets.dart';

/// Hoja inferior para filtrar por tipo, categoría y método de pago.
Future<TransactionFilter?> showTransactionFilterSheet(BuildContext context, TransactionFilter current) {
  return showModalBottomSheet<TransactionFilter>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _FilterSheet(initial: current),
  );
}

class _FilterSheet extends ConsumerStatefulWidget {
  const _FilterSheet({required this.initial});

  final TransactionFilter initial;

  @override
  ConsumerState<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends ConsumerState<_FilterSheet> {
  late TxType? _type = widget.initial.type;
  late String? _categoryId = widget.initial.categoryId;
  late PaymentMethod? _method = widget.initial.paymentMethod;

  @override
  Widget build(BuildContext context) {
    final categories = (ref.watch(categoriesProvider).valueOrNull ?? const [])
        .where((c) => _type == null || c.type == _type)
        .toList();
    final text = Theme.of(context).textTheme;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
        child: SingleChildScrollView(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Filtros', style: text.titleLarge),
            const SizedBox(height: 16),
            Text('Tipo', style: text.titleSmall),
            const SizedBox(height: 8),
            SegmentedButton<TxType?>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: null, label: Text('Todos')),
                ButtonSegment(value: TxType.income, label: Text('Ingresos')),
                ButtonSegment(value: TxType.expense, label: Text('Egresos')),
              ],
              selected: {_type},
              onSelectionChanged: (s) => setState(() {
                _type = s.first;
                if (_categoryId != null && !categories.any((c) => c.id == _categoryId && c.type == _type)) {
                  _categoryId = null;
                }
              }),
            ),
            const SizedBox(height: 20),
            Row(children: [
              Expanded(child: Text('Categoría', style: text.titleSmall)),
              if (_categoryId != null)
                TextButton(onPressed: () => setState(() => _categoryId = null), child: const Text('Quitar')),
            ]),
            const SizedBox(height: 8),
            CategoryPicker(
              categories: categories,
              selectedId: _categoryId,
              onSelected: (c) => setState(() => _categoryId = c.id == _categoryId ? null : c.id),
            ),
            const SizedBox(height: 20),
            Text('Método de pago', style: text.titleSmall),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final m in PaymentMethod.values)
                FilterChip(
                  avatar: Icon(m.icon, size: 18),
                  label: Text(m.label),
                  selected: _method == m,
                  onSelected: (sel) => setState(() => _method = sel ? m : null),
                ),
            ]),
            const SizedBox(height: 24),
            Row(children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context, widget.initial.clearExtras()),
                  child: const Text('Limpiar'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: () => Navigator.pop(
                    context,
                    TransactionFilter(
                      range: widget.initial.range,
                      type: _type,
                      categoryId: _categoryId,
                      paymentMethod: _method,
                      query: widget.initial.query,
                    ),
                  ),
                  child: const Text('Aplicar'),
                ),
              ),
            ]),
          ]),
        ),
      ),
    );
  }
}

/// Chips con los filtros activos (para mostrarlos sobre la lista).
class ActiveFilterChips extends ConsumerWidget {
  const ActiveFilterChips({super.key, required this.filter, required this.onChanged});

  final TransactionFilter filter;
  final ValueChanged<TransactionFilter> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!filter.hasExtraFilters) return const SizedBox.shrink();
    final categories = ref.watch(categoryMapProvider);
    return SizedBox(
      height: 48,
      child: ListView(scrollDirection: Axis.horizontal, children: [
        if (filter.type != null)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: InputChip(
              label: Text(filter.type!.pluralLabel),
              onDeleted: () => onChanged(filter.copyWith(clearType: true)),
            ),
          ),
        if (filter.categoryId != null)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: InputChip(
              label: Text(categories[filter.categoryId]?.name ?? 'Categoría'),
              onDeleted: () => onChanged(filter.copyWith(clearCategory: true)),
            ),
          ),
        if (filter.paymentMethod != null)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: InputChip(
              label: Text(filter.paymentMethod!.label),
              onDeleted: () => onChanged(filter.copyWith(clearPaymentMethod: true)),
            ),
          ),
        if (filter.query?.isNotEmpty ?? false)
          InputChip(
            label: Text('“${filter.query}”'),
            onDeleted: () => onChanged(TransactionFilter(
              range: filter.range,
              type: filter.type,
              categoryId: filter.categoryId,
              paymentMethod: filter.paymentMethod,
            )),
          ),
      ]),
    );
  }
}

/// Describe los filtros en texto (para el PDF).
String describeFilter(TransactionFilter f, Map<String, String> categoryNames) {
  final parts = <String>[
    if (f.type != null) f.type!.pluralLabel,
    if (f.categoryId != null) categoryNames[f.categoryId] ?? 'Categoría',
    if (f.paymentMethod != null) f.paymentMethod!.label,
  ];
  return parts.join(', ');
}
