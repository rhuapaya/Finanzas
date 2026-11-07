import 'package:intl/intl.dart';

/// Utilidades de fechas "solo día" (sin hora), en hora local.
abstract final class Dates {
  static DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  static DateTime today() => dateOnly(DateTime.now());

  /// "2026-11-07"
  static String toIsoDate(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  static DateTime parseIsoDate(String s) {
    final parts = s.substring(0, 10).split('-');
    return DateTime(int.parse(parts[0]), int.parse(parts[1]), int.parse(parts[2]));
  }

  static int daysInMonth(int year, int month) => DateTime(year, month + 1, 0).day;

  /// Suma meses conservando el día ancla (31 → 28/29/30 según el mes).
  static DateTime addMonths(DateTime d, int months, {int? anchorDay}) {
    final totalMonths = d.year * 12 + (d.month - 1) + months;
    final year = totalMonths ~/ 12;
    final month = totalMonths % 12 + 1;
    final day = anchorDay ?? d.day;
    final maxDay = daysInMonth(year, month);
    return DateTime(year, month, day > maxDay ? maxDay : day);
  }

  static String nowUtcIso() => DateTime.now().toUtc().toIso8601String();

  static String formatShort(DateTime d) => DateFormat('d MMM yyyy', 'es').format(d);
  static String formatLong(DateTime d) => DateFormat("EEEE d 'de' MMMM, yyyy", 'es').format(d);
  static String formatDayHeader(DateTime d) {
    final t = today();
    final date = dateOnly(d);
    if (date == t) return 'Hoy';
    if (date == DateTime(t.year, t.month, t.day - 1)) return 'Ayer';
    return DateFormat("EEEE d 'de' MMMM", 'es').format(d);
  }

  static String monthYear(int year, int month) {
    final s = DateFormat('MMMM yyyy', 'es').format(DateTime(year, month));
    return s[0].toUpperCase() + s.substring(1);
  }

  static String monthShort(int year, int month) =>
      DateFormat('MMM', 'es').format(DateTime(year, month)).replaceAll('.', '');
}
