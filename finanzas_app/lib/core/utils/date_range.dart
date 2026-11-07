import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';

import 'dates.dart';

enum PeriodType {
  day('Día'),
  week('Semana'),
  month('Mes'),
  year('Año'),
  custom('Rango');

  const PeriodType(this.label);
  final String label;
}

/// Rango de fechas inclusivo (solo días).
@immutable
class DateRange {
  DateRange(DateTime start, DateTime end)
      : start = Dates.dateOnly(start),
        end = Dates.dateOnly(end) {
    if (this.end.isBefore(this.start)) {
      throw ArgumentError('La fecha final no puede ser anterior a la inicial');
    }
  }

  final DateTime start;
  final DateTime end;

  bool contains(DateTime d) {
    final x = Dates.dateOnly(d);
    return !x.isBefore(start) && !x.isAfter(end);
  }

  int get days => end.difference(start).inDays + 1;

  String get startIso => Dates.toIsoDate(start);
  String get endIso => Dates.toIsoDate(end);

  /// Rango del periodo que contiene [reference]. La semana empieza el lunes.
  static DateRange forPeriod(PeriodType type, DateTime reference) {
    final r = Dates.dateOnly(reference);
    switch (type) {
      case PeriodType.day:
        return DateRange(r, r);
      case PeriodType.week:
        final start = DateTime(r.year, r.month, r.day - (r.weekday - DateTime.monday));
        return DateRange(start, DateTime(start.year, start.month, start.day + 6));
      case PeriodType.month:
      case PeriodType.custom:
        return DateRange(DateTime(r.year, r.month, 1), DateTime(r.year, r.month + 1, 0));
      case PeriodType.year:
        return DateRange(DateTime(r.year, 1, 1), DateTime(r.year, 12, 31));
    }
  }

  /// Desplaza el rango [delta] periodos (negativo = hacia atrás).
  DateRange shift(PeriodType type, int delta) {
    switch (type) {
      case PeriodType.day:
        return DateRange(
          DateTime(start.year, start.month, start.day + delta),
          DateTime(end.year, end.month, end.day + delta),
        );
      case PeriodType.week:
        return DateRange(
          DateTime(start.year, start.month, start.day + 7 * delta),
          DateTime(end.year, end.month, end.day + 7 * delta),
        );
      case PeriodType.month:
        return forPeriod(PeriodType.month, DateTime(start.year, start.month + delta, 1));
      case PeriodType.year:
        return forPeriod(PeriodType.year, DateTime(start.year + delta, 1, 1));
      case PeriodType.custom:
        final length = days;
        return DateRange(
          DateTime(start.year, start.month, start.day + length * delta),
          DateTime(end.year, end.month, end.day + length * delta),
        );
    }
  }

  /// Periodo inmediatamente anterior de igual duración (para comparar).
  DateRange previous(PeriodType type) => shift(type, -1);

  String label(PeriodType type) {
    final f = DateFormat('d MMM yyyy', 'es');
    switch (type) {
      case PeriodType.day:
        return Dates.formatDayHeader(start);
      case PeriodType.week:
        return '${DateFormat('d MMM', 'es').format(start)} – ${f.format(end)}';
      case PeriodType.month:
        return Dates.monthYear(start.year, start.month);
      case PeriodType.year:
        return '${start.year}';
      case PeriodType.custom:
        return '${f.format(start)} – ${f.format(end)}';
    }
  }

  @override
  bool operator ==(Object other) =>
      other is DateRange && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);

  @override
  String toString() => 'DateRange($startIso..$endIso)';
}

/// Periodo seleccionado en el panel/reportes.
@immutable
class PeriodSelection {
  const PeriodSelection(this.type, this.range);

  factory PeriodSelection.current(PeriodType type, {DateTime? now}) =>
      PeriodSelection(type, DateRange.forPeriod(type, now ?? DateTime.now()));

  final PeriodType type;
  final DateRange range;

  PeriodSelection shift(int delta) => PeriodSelection(type, range.shift(type, delta));

  String get label => range.label(type);

  @override
  bool operator ==(Object other) =>
      other is PeriodSelection && other.type == type && other.range == range;

  @override
  int get hashCode => Object.hash(type, range);
}
