import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/utils/dates.dart';
import '../../data/models/enums.dart';
import '../../data/models/recurring_transaction.dart';
import '../../providers.dart';
import '../../shared/widgets/category_widgets.dart';
import '../../shared/widgets/feedback.dart';
import '../../shared/widgets/money_widgets.dart';
import '../../shared/widgets/state_views.dart';

class RecurringScreen extends ConsumerWidget {
  const RecurringScreen({super.key});

  Future<void> _toggle(BuildContext context, WidgetRef ref, RecurringTransaction r) async {
    final service = ref.read(recurringServiceProvider);
    try {
      final next = r.status == RecurringStatus.active ? RecurringStatus.paused : RecurringStatus.active;
      await service.setStatus(r, next);
      if (next == RecurringStatus.active) {
        final user = ref.read(currentUserProvider);
        if (user != null) await service.processDue(user);
      }
      if (context.mounted) {
        showInfoSnack(context, next == RecurringStatus.active ? 'Recurrente reanudado' : 'Recurrente pausado');
      }
    } catch (e) {
      if (context.mounted) showErrorSnack(context, e);
    }
  }

  Future<void> _delete(BuildContext context, WidgetRef ref, RecurringTransaction r) async {
    final ok = await confirmAction(
      context,
      title: 'Eliminar recurrente',
      message: 'Se dejarán de generar movimientos automáticos. Los movimientos ya registrados se conservarán.',
    );
    if (!ok) return;
    try {
      await ref.read(recurringServiceProvider).delete(r.id);
      if (context.mounted) showInfoSnack(context, 'Recurrente eliminado');
    } catch (e) {
      if (context.mounted) showErrorSnack(context, e);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(recurringListProvider);
    final categories = ref.watch(categoryMapProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Movimientos recurrentes')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/recurring/new'),
        icon: const Icon(Icons.add),
        label: const Text('Nuevo'),
      ),
      body: list.when(
        loading: () => const LoadingView(),
        error: (e, _) => ErrorView(error: e, onRetry: () => ref.invalidate(recurringListProvider)),
        data: (items) {
          if (items.isEmpty) {
            return EmptyState(
              icon: Icons.event_repeat,
              title: 'Sin movimientos recurrentes',
              message: 'Registra tu sueldo, alquiler o suscripciones para que se agreguen automáticamente.',
              actionLabel: 'Crear recurrente',
              onAction: () => context.push('/recurring/new'),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.only(bottom: 96),
            itemCount: items.length,
            separatorBuilder: (_, __) => const Divider(height: 1, indent: 72),
            itemBuilder: (context, i) {
              final r = items[i];
              final c = categories[r.categoryId];
              final scheme = Theme.of(context).colorScheme;
              final statusColor = switch (r.status) {
                RecurringStatus.active => scheme.primary,
                RecurringStatus.paused => scheme.outline,
                RecurringStatus.finished => scheme.onSurfaceVariant,
              };
              return ListTile(
                leading: CategoryAvatar(category: c),
                title: Text(r.description ?? c?.name ?? 'Recurrente', maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(
                  '${r.frequency.label} · ${r.status == RecurringStatus.active ? 'Próximo: ${Dates.formatShort(r.nextDate)}' : r.status.label}',
                  style: TextStyle(color: statusColor),
                ),
                onTap: () => context.push('/recurring/${r.id}'),
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  AmountText(r.amount, type: r.type),
                  PopupMenuButton<String>(
                    tooltip: 'Opciones',
                    onSelected: (v) {
                      switch (v) {
                        case 'toggle':
                          _toggle(context, ref, r);
                        case 'edit':
                          context.push('/recurring/${r.id}');
                        case 'delete':
                          _delete(context, ref, r);
                      }
                    },
                    itemBuilder: (_) => [
                      if (r.status != RecurringStatus.finished)
                        PopupMenuItem(
                          value: 'toggle',
                          child: Text(r.status == RecurringStatus.active ? 'Pausar' : 'Reanudar'),
                        ),
                      const PopupMenuItem(value: 'edit', child: Text('Editar')),
                      const PopupMenuItem(value: 'delete', child: Text('Eliminar')),
                    ],
                  ),
                ]),
              );
            },
          );
        },
      ),
    );
  }
}
