import 'dart:convert';
import 'dart:io';

import 'package:csv/csv.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

import '../../core/finance/finance_calculator.dart';
import '../../core/money/currency.dart';
import '../../core/utils/dates.dart';
import '../models/category.dart';
import '../models/enums.dart';
import '../models/fin_transaction.dart';

/// Datos de un reporte a exportar.
class ReportExport {
  const ReportExport({
    required this.title,
    required this.periodLabel,
    required this.transactions,
    required this.categories,
    required this.currency,
    this.filtersDescription,
  });

  final String title;
  final String periodLabel;
  final List<FinTransaction> transactions;
  final Map<String, Category> categories;
  final CurrencyInfo currency;
  final String? filtersDescription;
}

/// Exporta reportes en CSV y PDF y los comparte.
class ExportService {
  const ExportService();

  static String _stamp() {
    final n = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${n.year}${two(n.month)}${two(n.day)}_${two(n.hour)}${two(n.minute)}';
  }

  /// Filas del CSV (cabecera + datos). Separado para poder probarlo.
  static List<List<String>> csvRows(ReportExport r) {
    final rows = <List<String>>[
      ['Fecha', 'Tipo', 'Categoría', 'Descripción', 'Método de pago', 'Monto', 'Moneda'],
    ];
    for (final t in r.transactions) {
      rows.add([
        Dates.toIsoDate(t.date),
        t.type.label,
        r.categories[t.categoryId]?.name ?? 'Sin categoría',
        t.description ?? '',
        t.paymentMethod.label,
        t.signedAmount.toDecimalString(),
        r.currency.code,
      ]);
    }
    return rows;
  }

  Future<File> buildCsv(ReportExport r) async {
    final csv = const ListToCsvConverter().convert(csvRows(r));
    final dir = await getTemporaryDirectory();
    final file = File(p.join(dir.path, 'reporte_finanzas_${_stamp()}.csv'));
    // BOM para que Excel reconozca UTF-8 (tildes y ñ).
    await file.writeAsString('﻿$csv', encoding: utf8);
    return file;
  }

  Future<File> buildPdf(ReportExport r) async {
    final summary = FinanceCalculator.summarize(r.transactions);
    final byCategory = FinanceCalculator.totalsByCategory(r.transactions, TxType.expense);
    final cur = r.currency;
    final doc = pw.Document(title: r.title, author: 'Mis Finanzas');

    pw.Widget kpi(String label, String value, PdfColor color) => pw.Expanded(
          child: pw.Container(
            padding: const pw.EdgeInsets.all(10),
            margin: const pw.EdgeInsets.symmetric(horizontal: 4),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: PdfColors.grey300),
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
            ),
            child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              pw.Text(label, style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
              pw.SizedBox(height: 4),
              pw.Text(value, style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold, color: color)),
            ]),
          ),
        );

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        header: (context) => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Text(r.title, style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 2),
          pw.Text('Periodo: ${r.periodLabel}', style: const pw.TextStyle(fontSize: 10)),
          if (r.filtersDescription != null && r.filtersDescription!.isNotEmpty)
            pw.Text('Filtros: ${r.filtersDescription}', style: const pw.TextStyle(fontSize: 10)),
          pw.Divider(),
        ]),
        footer: (context) => pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Text('Página ${context.pageNumber} de ${context.pagesCount}',
              style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
        ),
        build: (context) => [
          pw.Row(children: [
            kpi('Ingresos', summary.income.format(cur), PdfColors.green800),
            kpi('Egresos', summary.expense.format(cur), PdfColors.red800),
            kpi('Balance', summary.balance.format(cur),
                summary.balance.isNegative ? PdfColors.red800 : PdfColors.blueGrey800),
          ]),
          pw.SizedBox(height: 16),
          if (byCategory.isNotEmpty) ...[
            pw.Text('Egresos por categoría',
                style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 6),
            pw.TableHelper.fromTextArray(
              headers: ['Categoría', 'Movimientos', 'Monto', '%'],
              data: byCategory
                  .map((c) => [
                        r.categories[c.categoryId]?.name ?? 'Sin categoría',
                        '${c.count}',
                        c.total.format(cur),
                        '${c.percent} %',
                      ])
                  .toList(),
              headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10),
              cellStyle: const pw.TextStyle(fontSize: 9),
              headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
              cellAlignments: {
                1: pw.Alignment.centerRight,
                2: pw.Alignment.centerRight,
                3: pw.Alignment.centerRight,
              },
            ),
            pw.SizedBox(height: 16),
          ],
          pw.Text('Detalle de movimientos (${r.transactions.length})',
              style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 6),
          pw.TableHelper.fromTextArray(
            headers: ['Fecha', 'Tipo', 'Categoría', 'Descripción', 'Método', 'Monto'],
            data: r.transactions
                .map((t) => [
                      Dates.toIsoDate(t.date),
                      t.type.label,
                      r.categories[t.categoryId]?.name ?? '-',
                      t.description ?? '',
                      t.paymentMethod.label,
                      t.signedAmount.format(cur),
                    ])
                .toList(),
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9),
            cellStyle: const pw.TextStyle(fontSize: 8),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
            cellAlignments: {5: pw.Alignment.centerRight},
          ),
        ],
      ),
    );

    final dir = await getTemporaryDirectory();
    final file = File(p.join(dir.path, 'reporte_finanzas_${_stamp()}.pdf'));
    await file.writeAsBytes(await doc.save());
    return file;
  }

  Future<void> share(File file, {String? subject}) async {
    await Share.shareXFiles([XFile(file.path)], subject: subject ?? 'Reporte de Mis Finanzas');
  }
}
