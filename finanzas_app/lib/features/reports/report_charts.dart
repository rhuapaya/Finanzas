import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../core/finance/finance_calculator.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/dates.dart';

String _compact(double v) {
  final a = v.abs();
  if (a >= 1000000) return '${(v / 1000000).toStringAsFixed(1)}M';
  if (a >= 1000) return '${(v / 1000).toStringAsFixed(a >= 10000 ? 0 : 1)}k';
  return v.toStringAsFixed(0);
}

class _Legend extends StatelessWidget {
  const _Legend(this.items);

  final List<(Color, String)> items;

  @override
  Widget build(BuildContext context) {
    return Wrap(spacing: 16, children: [
      for (final (color, label) in items)
        Row(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 12, height: 12, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3))),
          const SizedBox(width: 6),
          Text(label, style: Theme.of(context).textTheme.bodySmall),
        ]),
    ]);
  }
}

/// Barras agrupadas: ingresos vs egresos por mes.
class IncomeExpenseBarChart extends StatelessWidget {
  const IncomeExpenseBarChart({super.key, required this.months});

  final List<MonthlyTotal> months;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final maxY = months.fold<double>(0, (m, t) {
      final v = t.income.toDouble() > t.expense.toDouble() ? t.income.toDouble() : t.expense.toDouble();
      return v > m ? v : m;
    });
    final groups = <BarChartGroupData>[
      for (var i = 0; i < months.length; i++)
        BarChartGroupData(x: i, barsSpace: 3, barRods: [
          BarChartRodData(
            toY: months[i].income.toDouble(),
            color: scheme.income,
            width: 7,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
          ),
          BarChartRodData(
            toY: months[i].expense.toDouble(),
            color: scheme.expense,
            width: 7,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
          ),
        ]),
    ];
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _Legend([(scheme.income, 'Ingresos'), (scheme.expense, 'Egresos')]),
      const SizedBox(height: 12),
      Semantics(
        label: 'Gráfico de barras de ingresos y egresos por mes',
        child: SizedBox(
          height: 220,
          child: BarChart(
            BarChartData(
              maxY: maxY == 0 ? 1 : maxY * 1.15,
              barGroups: groups,
              gridData: FlGridData(
                drawVerticalLine: false,
                getDrawingHorizontalLine: (_) => FlLine(color: scheme.outlineVariant, strokeWidth: 0.6),
              ),
              borderData: FlBorderData(show: false),
              titlesData: FlTitlesData(
                topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 40,
                    getTitlesWidget: (value, meta) => Text(
                      _compact(value),
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  ),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 28,
                    getTitlesWidget: (value, meta) {
                      final i = value.toInt();
                      if (i < 0 || i >= months.length) return const SizedBox.shrink();
                      return Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          Dates.monthShort(months[i].year, months[i].month),
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ]);
  }
}

/// Línea de tendencia mensual: egresos y balance neto.
class MonthlyTrendChart extends StatelessWidget {
  const MonthlyTrendChart({super.key, required this.months});

  final List<MonthlyTotal> months;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final expenseSpots = [
      for (var i = 0; i < months.length; i++) FlSpot(i.toDouble(), months[i].expense.toDouble()),
    ];
    final netSpots = [
      for (var i = 0; i < months.length; i++) FlSpot(i.toDouble(), months[i].net.toDouble()),
    ];
    final values = [...expenseSpots, ...netSpots].map((s) => s.y);
    final maxY = values.fold<double>(0, (m, v) => v > m ? v : m);
    final minY = values.fold<double>(0, (m, v) => v < m ? v : m);

    LineChartBarData line(List<FlSpot> spots, Color color) => LineChartBarData(
          spots: spots,
          isCurved: true,
          preventCurveOverShooting: true,
          color: color,
          barWidth: 3,
          dotData: const FlDotData(show: false),
          belowBarData: BarAreaData(show: true, color: color.withAlpha(30)),
        );

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _Legend([(scheme.expense, 'Egresos'), (scheme.primary, 'Balance neto')]),
      const SizedBox(height: 12),
      Semantics(
        label: 'Gráfico de tendencia mensual de egresos y balance',
        child: SizedBox(
          height: 220,
          child: LineChart(
            LineChartData(
              minY: minY < 0 ? minY * 1.15 : 0,
              maxY: maxY == 0 ? 1 : maxY * 1.15,
              lineBarsData: [line(expenseSpots, scheme.expense), line(netSpots, scheme.primary)],
              gridData: FlGridData(
                drawVerticalLine: false,
                getDrawingHorizontalLine: (_) => FlLine(color: scheme.outlineVariant, strokeWidth: 0.6),
              ),
              borderData: FlBorderData(show: false),
              titlesData: FlTitlesData(
                topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 40,
                    getTitlesWidget: (value, meta) =>
                        Text(_compact(value), style: Theme.of(context).textTheme.labelSmall),
                  ),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    interval: 2,
                    reservedSize: 28,
                    getTitlesWidget: (value, meta) {
                      final i = value.toInt();
                      if (i < 0 || i >= months.length || value != i.toDouble()) return const SizedBox.shrink();
                      return Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(Dates.monthShort(months[i].year, months[i].month),
                            style: Theme.of(context).textTheme.labelSmall),
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ]);
  }
}
