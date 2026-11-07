import 'package:flutter/material.dart';

import '../../core/utils/date_range.dart';

/// Selector de periodo: Día · Semana · Mes · Año · Rango, con navegación.
class PeriodSelector extends StatelessWidget {
  const PeriodSelector({super.key, required this.selection, required this.onChanged});

  final PeriodSelection selection;
  final ValueChanged<PeriodSelection> onChanged;

  Future<void> _pickCustom(BuildContext context) async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime(now.year + 5, 12, 31),
      initialDateRange: DateTimeRange(start: selection.range.start, end: selection.range.end),
      helpText: 'Selecciona el rango',
      saveText: 'Aplicar',
    );
    if (picked != null) {
      onChanged(PeriodSelection(PeriodType.custom, DateRange(picked.start, picked.end)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SegmentedButton<PeriodType>(
            showSelectedIcon: false,
            segments: [
              for (final t in PeriodType.values) ButtonSegment(value: t, label: Text(t.label)),
            ],
            selected: {selection.type},
            onSelectionChanged: (s) {
              final type = s.first;
              if (type == PeriodType.custom) {
                _pickCustom(context);
              } else {
                onChanged(PeriodSelection.current(type));
              }
            },
          ),
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            IconButton(
              tooltip: 'Periodo anterior',
              icon: const Icon(Icons.chevron_left),
              onPressed: () => onChanged(selection.shift(-1)),
            ),
            Expanded(
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: selection.type == PeriodType.custom ? () => _pickCustom(context) : null,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Text(
                    selection.label,
                    textAlign: TextAlign.center,
                    style: textTheme.titleSmall,
                  ),
                ),
              ),
            ),
            IconButton(
              tooltip: 'Periodo siguiente',
              icon: const Icon(Icons.chevron_right),
              onPressed: () => onChanged(selection.shift(1)),
            ),
          ],
        ),
      ],
    );
  }
}
