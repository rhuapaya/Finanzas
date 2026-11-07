import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../core/finance/finance_calculator.dart';
import '../../data/models/category.dart';
import '../../shared/widgets/money_widgets.dart';

/// Gráfico de dona con la distribución de egresos por categoría + leyenda.
class ExpensePieChart extends StatefulWidget {
  const ExpensePieChart({super.key, required this.totals, required this.categories, this.maxSlices = 6});

  final List<CategoryTotal> totals;
  final Map<String, Category> categories;
  final int maxSlices;

  @override
  State<ExpensePieChart> createState() => _ExpensePieChartState();
}

class _ExpensePieChartState extends State<ExpensePieChart> {
  int? _touched;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final visible = widget.totals.take(widget.maxSlices).toList();
    final rest = widget.totals.skip(widget.maxSlices).toList();
    final restTotal = rest.fold<int>(0, (a, c) => a + c.total.cents);
    final restPercent = rest.fold<int>(0, (a, c) => a + c.percent);

    final sections = <PieChartSectionData>[];
    for (var i = 0; i < visible.length; i++) {
      final t = visible[i];
      final c = widget.categories[t.categoryId];
      final touched = i == _touched;
      sections.add(PieChartSectionData(
        value: t.total.toDouble(),
        color: c == null ? scheme.outline : Color(c.color),
        radius: touched ? 58 : 50,
        title: t.percent >= 7 ? '${t.percent}%' : '',
        titleStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white),
      ));
    }
    if (restTotal > 0) {
      sections.add(PieChartSectionData(
        value: restTotal / 100,
        color: scheme.outlineVariant,
        radius: 50,
        title: restPercent >= 7 ? '$restPercent%' : '',
        titleStyle: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: scheme.onSurface),
      ));
    }

    return Column(children: [
      Semantics(
        label: 'Gráfico de egresos por categoría',
        child: SizedBox(
          height: 190,
          child: PieChart(
            PieChartData(
              sections: sections,
              centerSpaceRadius: 46,
              sectionsSpace: 2,
              pieTouchData: PieTouchData(
                touchCallback: (event, response) {
                  setState(() {
                    if (!event.isInterestedForInteractions || response?.touchedSection == null) {
                      _touched = null;
                    } else {
                      _touched = response!.touchedSection!.touchedSectionIndex;
                    }
                  });
                },
              ),
            ),
          ),
        ),
      ),
      const SizedBox(height: 12),
      for (final t in visible)
        _LegendRow(
          color: widget.categories[t.categoryId] == null
              ? scheme.outline
              : Color(widget.categories[t.categoryId]!.color),
          label: widget.categories[t.categoryId]?.name ?? 'Sin categoría',
          percent: t.percent,
          child: AmountText(t.total, colored: false, style: Theme.of(context).textTheme.bodyMedium),
        ),
      if (restTotal > 0)
        _LegendRow(
          color: scheme.outlineVariant,
          label: 'Otras (${rest.length})',
          percent: restPercent,
          child: Text('', style: Theme.of(context).textTheme.bodyMedium),
        ),
    ]);
  }
}

class _LegendRow extends StatelessWidget {
  const _LegendRow({required this.color, required this.label, required this.percent, required this.child});

  final Color color;
  final String label;
  final int percent;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        Container(width: 12, height: 12, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 10),
        Expanded(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis)),
        Text('$percent %  ', style: Theme.of(context).textTheme.bodySmall),
        child,
      ]),
    );
  }
}
