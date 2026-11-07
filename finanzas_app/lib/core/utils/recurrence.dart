import '../../data/models/enums.dart';
import 'dates.dart';

/// Resultado de calcular las ocurrencias vencidas de un movimiento recurrente.
class DueOccurrences {
  const DueOccurrences({required this.dates, required this.nextDate, required this.finished});

  /// Fechas que deben registrarse ahora (<= hoy).
  final List<DateTime> dates;

  /// Siguiente fecha pendiente tras registrar [dates].
  final DateTime nextDate;

  /// `true` si se superó la fecha de fin.
  final bool finished;
}

abstract final class Recurrence {
  /// Siguiente fecha después de [from] para la [frequency] dada.
  /// [anchorDay] conserva el día original en frecuencias mensual/anual.
  static DateTime next(DateTime from, Frequency frequency, {int? anchorDay}) {
    final d = Dates.dateOnly(from);
    switch (frequency) {
      case Frequency.daily:
        return DateTime(d.year, d.month, d.day + 1);
      case Frequency.weekly:
        return DateTime(d.year, d.month, d.day + 7);
      case Frequency.biweekly:
        return DateTime(d.year, d.month, d.day + 14);
      case Frequency.monthly:
        return Dates.addMonths(d, 1, anchorDay: anchorDay);
      case Frequency.yearly:
        return Dates.addMonths(d, 12, anchorDay: anchorDay);
    }
  }

  /// Calcula todas las ocurrencias desde [nextDate] hasta [today] inclusive.
  static DueOccurrences due({
    required DateTime nextDate,
    required DateTime today,
    required Frequency frequency,
    required int anchorDay,
    DateTime? endDate,
    int maxOccurrences = 400,
  }) {
    final t = Dates.dateOnly(today);
    final end = endDate == null ? null : Dates.dateOnly(endDate);
    var cursor = Dates.dateOnly(nextDate);
    final dates = <DateTime>[];

    while (!cursor.isAfter(t) && dates.length < maxOccurrences) {
      if (end != null && cursor.isAfter(end)) break;
      dates.add(cursor);
      cursor = next(cursor, frequency, anchorDay: anchorDay);
    }
    final finished = end != null && cursor.isAfter(end);
    return DueOccurrences(dates: dates, nextDate: cursor, finished: finished);
  }
}
