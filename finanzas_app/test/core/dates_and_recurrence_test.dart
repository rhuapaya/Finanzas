import 'package:finanzas_app/core/utils/date_range.dart';
import 'package:finanzas_app/core/utils/dates.dart';
import 'package:finanzas_app/core/utils/recurrence.dart';
import 'package:finanzas_app/data/models/enums.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

void main() {
  setUpAll(() => initializeDateFormatting('es'));

  group('DateRange', () {
    test('la semana empieza el lunes', () {
      final r = DateRange.forPeriod(PeriodType.week, DateTime(2026, 11, 7)); // sábado
      expect(r.start, DateTime(2026, 11, 2));
      expect(r.end, DateTime(2026, 11, 8));
      expect(r.days, 7);
    });

    test('mes y año completos', () {
      final feb = DateRange.forPeriod(PeriodType.month, DateTime(2028, 2, 10));
      expect(feb.end, DateTime(2028, 2, 29));
      final year = DateRange.forPeriod(PeriodType.year, DateTime(2026, 6, 1));
      expect(year.start, DateTime(2026, 1, 1));
      expect(year.end, DateTime(2026, 12, 31));
    });

    test('desplazar periodos', () {
      final nov = DateRange.forPeriod(PeriodType.month, DateTime(2026, 11, 7));
      expect(nov.shift(PeriodType.month, -1).start, DateTime(2026, 10, 1));
      expect(nov.shift(PeriodType.month, 2).end, DateTime(2027, 1, 31));
      final day = DateRange.forPeriod(PeriodType.day, DateTime(2026, 12, 31));
      expect(day.shift(PeriodType.day, 1).start, DateTime(2027, 1, 1));
      final custom = DateRange(DateTime(2026, 1, 1), DateTime(2026, 1, 10));
      expect(custom.shift(PeriodType.custom, 1).start, DateTime(2026, 1, 11));
    });

    test('contains es inclusivo', () {
      final r = DateRange(DateTime(2026, 1, 1), DateTime(2026, 1, 31));
      expect(r.contains(DateTime(2026, 1, 1, 23, 59)), isTrue);
      expect(r.contains(DateTime(2026, 1, 31)), isTrue);
      expect(r.contains(DateTime(2026, 2, 1)), isFalse);
    });

    test('rechaza rangos invertidos', () {
      expect(() => DateRange(DateTime(2026, 2, 1), DateTime(2026, 1, 1)), throwsArgumentError);
    });

    test('etiquetas en español', () {
      final r = DateRange.forPeriod(PeriodType.month, DateTime(2026, 11, 7));
      expect(r.label(PeriodType.month), 'Noviembre 2026');
      expect(r.label(PeriodType.year), '2026');
    });
  });

  group('Dates', () {
    test('formato ISO y parseo', () {
      expect(Dates.toIsoDate(DateTime(2026, 3, 9)), '2026-03-09');
      expect(Dates.parseIsoDate('2026-03-09'), DateTime(2026, 3, 9));
      expect(Dates.parseIsoDate('2026-03-09T10:00:00Z'), DateTime(2026, 3, 9));
    });

    test('addMonths conserva el día ancla', () {
      expect(Dates.addMonths(DateTime(2026, 1, 31), 1), DateTime(2026, 2, 28));
      expect(Dates.addMonths(DateTime(2026, 2, 28), 1, anchorDay: 31), DateTime(2026, 3, 31));
      expect(Dates.addMonths(DateTime(2026, 11, 15), 3), DateTime(2027, 2, 15));
      expect(Dates.addMonths(DateTime(2026, 1, 15), -2), DateTime(2025, 11, 15));
    });
  });

  group('Recurrence', () {
    test('siguiente fecha por frecuencia', () {
      final d = DateTime(2026, 1, 31);
      expect(Recurrence.next(d, Frequency.daily), DateTime(2026, 2, 1));
      expect(Recurrence.next(d, Frequency.weekly), DateTime(2026, 2, 7));
      expect(Recurrence.next(d, Frequency.biweekly), DateTime(2026, 2, 14));
      expect(Recurrence.next(d, Frequency.monthly, anchorDay: 31), DateTime(2026, 2, 28));
      expect(Recurrence.next(DateTime(2028, 2, 29), Frequency.yearly, anchorDay: 29), DateTime(2029, 2, 28));
    });

    test('ocurrencias vencidas hasta hoy', () {
      final due = Recurrence.due(
        nextDate: DateTime(2026, 8, 31),
        today: DateTime(2026, 11, 7),
        frequency: Frequency.monthly,
        anchorDay: 31,
      );
      expect(due.dates, [DateTime(2026, 8, 31), DateTime(2026, 9, 30), DateTime(2026, 10, 31)]);
      expect(due.nextDate, DateTime(2026, 11, 30));
      expect(due.finished, isFalse);
    });

    test('respeta la fecha de fin', () {
      final due = Recurrence.due(
        nextDate: DateTime(2026, 11, 1),
        today: DateTime(2026, 11, 30),
        frequency: Frequency.weekly,
        anchorDay: 1,
        endDate: DateTime(2026, 11, 10),
      );
      expect(due.dates, [DateTime(2026, 11, 1), DateTime(2026, 11, 8)]);
      expect(due.finished, isTrue);
    });

    test('nada vencido si la próxima fecha es futura', () {
      final due = Recurrence.due(
        nextDate: DateTime(2026, 12, 1),
        today: DateTime(2026, 11, 7),
        frequency: Frequency.monthly,
        anchorDay: 1,
      );
      expect(due.dates, isEmpty);
      expect(due.nextDate, DateTime(2026, 12, 1));
    });
  });
}
