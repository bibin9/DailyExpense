import 'package:daily_expense_tracker/core/local_date.dart';
import 'package:daily_expense_tracker/domain/models.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

void main() {
  group('period maths', () {
    test(
      'week is Monday–Sunday (Sunday belongs to the week before Monday)',
      () {
        final sun = LocalDate(2026, 10, 4); // Sunday
        final mon = LocalDate(2026, 10, 5); // Monday
        expect(sun.weekday, DateTime.sunday);
        expect(ReportPeriod.weekly(sun).start, LocalDate(2026, 9, 28));
        expect(ReportPeriod.weekly(sun).end, sun);
        expect(ReportPeriod.weekly(mon).start, mon);
        expect(ReportPeriod.weekly(mon).end, LocalDate(2026, 10, 11));
      },
    );

    test('week spanning month and year end', () {
      final p = ReportPeriod.weekly(LocalDate(2027, 1, 1)); // Friday
      expect(p.start, LocalDate(2026, 12, 28));
      expect(p.end, LocalDate(2027, 1, 3));
    });

    test('month end and leap years', () {
      expect(
        ReportPeriod.monthly(LocalDate(2028, 2, 10)).end,
        LocalDate(2028, 2, 29),
      );
      expect(
        ReportPeriod.monthly(LocalDate(2026, 2, 10)).end,
        LocalDate(2026, 2, 28),
      );
      expect(
        ReportPeriod.monthly(LocalDate(2100, 2, 1)).end,
        LocalDate(2100, 2, 28),
      );
      expect(
        ReportPeriod.monthly(LocalDate(2000, 2, 1)).end,
        LocalDate(2000, 2, 29),
      );
      expect(
        ReportPeriod.monthly(LocalDate(2026, 4, 30)).end,
        LocalDate(2026, 4, 30),
      );
      expect(
        ReportPeriod.monthly(LocalDate(2026, 12, 31)).start,
        LocalDate(2026, 12, 1),
      );
    });

    test('shifting periods', () {
      expect(
        ReportPeriod.monthly(LocalDate(2026, 1, 31)).shift(1).start,
        LocalDate(2026, 2, 1),
      );
      expect(
        ReportPeriod.monthly(LocalDate(2026, 1, 1)).shift(-1).start,
        LocalDate(2025, 12, 1),
      );
      expect(
        ReportPeriod.daily(LocalDate(2028, 2, 28)).shift(1).start,
        LocalDate(2028, 2, 29),
      );
      expect(
        ReportPeriod.weekly(LocalDate(2026, 10, 4)).shift(1).start,
        LocalDate(2026, 10, 5),
      );
    });

    test('invalid dates are rejected', () {
      expect(() => LocalDate(2026, 2, 29), throwsArgumentError);
      expect(() => LocalDate(2026, 13, 1), throwsArgumentError);
    });
  });

  group('database reports use inclusive local-date boundaries', () {
    late TestDb t;
    setUp(() => t = TestDb.create());
    tearDown(() => t.dispose());

    void add(LocalDate d, int fils, {int h = 12, int m = 0}) =>
        t.expenses.insert(
          ExpenseDraft(
            categoryId: t.category('Food').id,
            amountFils: fils,
            remarks: null,
          ),
          dubai(d.year, d.month, d.day, h, m),
          nowUtcMs: 1,
        );

    test('Sunday 23:59 is in the old week, Monday 00:00 in the new week', () {
      add(LocalDate(2026, 10, 4), 100, h: 23, m: 59); // Sun
      add(LocalDate(2026, 10, 5), 200, h: 0, m: 0); // Mon
      add(LocalDate(2026, 9, 28), 400, h: 0, m: 0); // previous Mon
      final old = t.expenses.report(
        ReportPeriod.weekly(LocalDate(2026, 10, 1)),
      );
      final next = t.expenses.report(
        ReportPeriod.weekly(LocalDate(2026, 10, 5)),
      );
      expect((old.count, old.totalFils), (2, 500));
      expect((next.count, next.totalFils), (1, 200));
    });

    test('month end: 31 Jan in January, 1 Feb in February', () {
      add(LocalDate(2026, 1, 31), 100, h: 23, m: 59);
      add(LocalDate(2026, 2, 1), 200, h: 0);
      add(LocalDate(2026, 1, 1), 50, h: 0);
      expect(
        t.expenses
            .report(ReportPeriod.monthly(LocalDate(2026, 1, 15)))
            .totalFils,
        150,
      );
      expect(
        t.expenses
            .report(ReportPeriod.monthly(LocalDate(2026, 2, 15)))
            .totalFils,
        200,
      );
    });

    test('leap day 29 Feb 2028 is in February and in its own daily report', () {
      add(LocalDate(2028, 2, 28), 100);
      add(LocalDate(2028, 2, 29), 200);
      add(LocalDate(2028, 3, 1), 400);
      expect(
        t.expenses.report(ReportPeriod.daily(LocalDate(2028, 2, 29))).totalFils,
        200,
      );
      expect(
        t.expenses
            .report(ReportPeriod.monthly(LocalDate(2028, 2, 1)))
            .totalFils,
        300,
      );
      expect(
        t.expenses
            .report(ReportPeriod.monthly(LocalDate(2028, 3, 1)))
            .totalFils,
        400,
      );
    });

    test('empty period reports zero, no entries', () {
      final r = t.expenses.report(ReportPeriod.daily(LocalDate(2026, 10, 2)));
      expect(r.isEmpty, isTrue);
      expect(
        (r.count, r.totalFils, r.entries.length, r.byCategory.length),
        (0, 0, 0, 0),
      );
    });
  });
}
