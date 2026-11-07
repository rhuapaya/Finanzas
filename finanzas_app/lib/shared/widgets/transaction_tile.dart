import 'package:flutter/material.dart';

import '../../core/utils/dates.dart';
import '../../data/models/category.dart';
import '../../data/models/fin_transaction.dart';
import 'category_widgets.dart';
import 'money_widgets.dart';

class TransactionTile extends StatelessWidget {
  const TransactionTile({
    super.key,
    required this.transaction,
    required this.category,
    this.onTap,
    this.showDate = true,
  });

  final FinTransaction transaction;
  final Category? category;
  final VoidCallback? onTap;
  final bool showDate;

  @override
  Widget build(BuildContext context) {
    final t = transaction;
    final scheme = Theme.of(context).colorScheme;
    final title = (t.description?.isNotEmpty ?? false) ? t.description! : (category?.name ?? 'Sin categoría');
    final subtitleParts = <String>[
      if (t.description?.isNotEmpty ?? false) category?.name ?? 'Sin categoría',
      if (showDate) Dates.formatShort(t.date),
      t.paymentMethod.label,
    ];
    return ListTile(
      onTap: onTap,
      leading: CategoryAvatar(category: category),
      title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Row(children: [
        if (t.recurringId != null)
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: Icon(Icons.repeat, size: 14, color: scheme.onSurfaceVariant, semanticLabel: 'Recurrente'),
          ),
        if (t.hasReceipt)
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: Icon(Icons.receipt, size: 14, color: scheme.onSurfaceVariant, semanticLabel: 'Con comprobante'),
          ),
        Expanded(
          child: Text(subtitleParts.join(' · '), maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
      ]),
      trailing: AmountText(
        t.amount,
        type: t.type,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
      ),
    );
  }
}
