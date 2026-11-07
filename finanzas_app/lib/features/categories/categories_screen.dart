import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/models/category.dart';
import '../../data/models/enums.dart';
import '../../providers.dart';
import '../../shared/widgets/category_widgets.dart';
import '../../shared/widgets/feedback.dart';
import '../../shared/widgets/state_views.dart';

class CategoriesScreen extends ConsumerWidget {
  const CategoriesScreen({super.key});

  Future<void> _delete(BuildContext context, WidgetRef ref, Category category, List<Category> all) async {
    final repo = ref.read(categoryRepositoryProvider);
    try {
      final usage = await repo.usageCount(category.id);
      if (!context.mounted) return;
      if (usage == 0) {
        final ok = await confirmAction(
          context,
          title: 'Eliminar categoría',
          message: '¿Eliminar "${category.name}"? Esta acción no se puede deshacer.',
        );
        if (!ok) return;
        await repo.delete(category.id);
        if (context.mounted) showInfoSnack(context, 'Categoría eliminada');
        return;
      }

      final candidates = all.where((c) => c.type == category.type && c.id != category.id).toList();
      if (candidates.isEmpty) {
        showInfoSnack(context,
            'La categoría tiene $usage registros. Crea otra categoría de ${category.type.pluralLabel.toLowerCase()} para reasignarlos.');
        return;
      }
      final target = await showDialog<Category>(
        context: context,
        builder: (_) => _ReassignDialog(category: category, usage: usage, candidates: candidates),
      );
      if (target == null || !context.mounted) return;
      await repo.reassignAndDelete(category.id, target.id);
      if (context.mounted) {
        showInfoSnack(context, 'Registros reasignados a "${target.name}" y categoría eliminada');
      }
    } catch (e) {
      if (context.mounted) showErrorSnack(context, e);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categories = ref.watch(categoriesProvider);
    return DefaultTabController(
      length: 2,
      child: Builder(builder: (context) {
        return Scaffold(
          appBar: AppBar(
            title: const Text('Categorías'),
            bottom: const TabBar(tabs: [Tab(text: 'Egresos'), Tab(text: 'Ingresos')]),
          ),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () {
              final index = DefaultTabController.of(context).index;
              final type = index == 0 ? TxType.expense : TxType.income;
              context.push('/categories/new?type=${type.code}');
            },
            icon: const Icon(Icons.add),
            label: const Text('Nueva'),
          ),
          body: categories.when(
            loading: () => const LoadingView(),
            error: (e, _) => ErrorView(error: e, onRetry: () => ref.invalidate(categoriesProvider)),
            data: (all) => TabBarView(children: [
              for (final type in const [TxType.expense, TxType.income])
                Builder(builder: (context) {
                  final list = all.where((c) => c.type == type).toList();
                  if (list.isEmpty) {
                    return EmptyState(
                      icon: Icons.category_outlined,
                      title: 'Sin categorías',
                      message: 'Crea categorías de ${type.pluralLabel.toLowerCase()} para organizar tus movimientos.',
                      actionLabel: 'Crear categoría',
                      onAction: () => context.push('/categories/new?type=${type.code}'),
                    );
                  }
                  return ListView.separated(
                    padding: const EdgeInsets.only(bottom: 96),
                    itemCount: list.length,
                    separatorBuilder: (_, __) => const Divider(height: 1, indent: 72),
                    itemBuilder: (context, i) {
                      final c = list[i];
                      return ListTile(
                        leading: CategoryAvatar(category: c),
                        title: Text(c.name),
                        subtitle: c.isDefault ? const Text('Predeterminada') : null,
                        onTap: () => context.push('/categories/${c.id}/edit'),
                        trailing: IconButton(
                          tooltip: 'Eliminar ${c.name}',
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () => _delete(context, ref, c, all),
                        ),
                      );
                    },
                  );
                }),
            ]),
          ),
        );
      }),
    );
  }
}

class _ReassignDialog extends StatefulWidget {
  const _ReassignDialog({required this.category, required this.usage, required this.candidates});

  final Category category;
  final int usage;
  final List<Category> candidates;

  @override
  State<_ReassignDialog> createState() => _ReassignDialogState();
}

class _ReassignDialogState extends State<_ReassignDialog> {
  Category? _target;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      icon: const Icon(Icons.swap_horiz),
      title: const Text('Reasignar antes de eliminar'),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('"${widget.category.name}" tiene ${widget.usage} registro(s) asociados '
              '(movimientos, presupuestos o recurrentes). Elige la categoría que los recibirá:'),
          const SizedBox(height: 12),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final c in widget.candidates)
                  ListTile(
                    leading: CategoryAvatar(category: c, size: 36),
                    title: Text(c.name),
                    selected: _target?.id == c.id,
                    trailing: _target?.id == c.id ? const Icon(Icons.check_circle) : null,
                    onTap: () => setState(() => _target = c),
                  ),
              ],
            ),
          ),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(
          onPressed: _target == null ? null : () => Navigator.pop(context, _target),
          child: const Text('Reasignar y eliminar'),
        ),
      ],
    );
  }
}
