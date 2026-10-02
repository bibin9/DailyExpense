import 'dart:math';

import 'package:daily_expense_tracker/core/capture.dart';
import 'package:daily_expense_tracker/core/local_date.dart';
import 'package:daily_expense_tracker/domain/models.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';

class _M {
  _M(this.id, this.cat, this.fils, this.date, this.instant);
  final String id;
  int cat;
  int fils;
  final LocalDate date;
  final int instant;
}

/// QA model-based test: random operations against the real encrypted DB
/// and an in-memory model; every report must match the model exactly.
void main() {
  test('reports match an independent model under random operations', () {
    final t = TestDb.create();
    final rnd = Random(424242);
    final model = <String, _M>{};
    var cats = t.categories.active();
    // Extra categories, some renamed/deactivated later.
    for (var i = 0; i < 6; i++) {
      t.categories.add('QA Cat $i', nowUtcMs: 1);
    }
    cats = t.categories.active();

    final start = DateTime.utc(2027, 11, 15).millisecondsSinceEpoch;
    const spanSeconds = 60 * 60 * 24 * 500; // ~500 days incl. leap 2028

    for (var op = 0; op < 4000; op++) {
      final r = rnd.nextInt(100);
      if (r < 75 || model.isEmpty) {
        final cat = cats[rnd.nextInt(cats.length)];
        if (!t.categories.byId(cat.id)!.isActive) continue;
        final instant = start + rnd.nextInt(spanSeconds) * 1000;
        // Any real-world offset: -12:00 … +14:00, incl. :30 and :45 zones.
        final offset = [-720, -300, 0, 240, 330, 345, 540, 840][rnd.nextInt(8)];
        final stamp = CaptureStamp.fromUtcAndOffset(instant, offset, 'TZ');
        final fils = 1 + rnd.nextInt(99999999);
        final e = t.expenses.insert(
          ExpenseDraft(
            categoryId: cat.id,
            amountFils: fils,
            remarks: cat.requiresRemark ? 'x' : null,
          ),
          stamp,
          nowUtcMs: 1,
        );
        model[e.id] = _M(e.id, cat.id, fils, stamp.localDate, instant);
      } else if (r < 87) {
        final m = model.values.elementAt(rnd.nextInt(model.length));
        final newFils = 1 + rnd.nextInt(5000000);
        final active = t.categories.active();
        final newCat = rnd.nextBool()
            ? m.cat
            : active[rnd.nextInt(active.length)].id;
        t.expenses.update(
          m.id,
          ExpenseDraft(categoryId: newCat, amountFils: newFils, remarks: 'e'),
          nowUtcMs: 2,
        );
        m
          ..fils = newFils
          ..cat = newCat;
      } else if (r < 97) {
        final m = model.values.elementAt(rnd.nextInt(model.length));
        expect(t.expenses.delete(m.id), isTrue);
        model.remove(m.id);
      } else if (r < 99) {
        final c = cats[rnd.nextInt(cats.length)];
        t.categories.rename(
          c.id,
          'Renamed ${rnd.nextInt(1 << 30)}',
          nowUtcMs: 3,
        );
      } else {
        final active = t.categories.active();
        if (active.length > 3) {
          t.categories.setActive(
            active[rnd.nextInt(active.length)].id,
            false,
            nowUtcMs: 4,
          );
        }
      }
    }

    void verify(ReportPeriod p) {
      final inside = model.values.where((m) => p.contains(m.date)).toList()
        ..sort((a, b) {
          final c = b.instant.compareTo(a.instant);
          return c != 0 ? c : b.id.compareTo(a.id);
        });
      final r = t.expenses.report(p);
      expect(r.count, inside.length);
      expect(r.totalFils, inside.fold<int>(0, (s, m) => s + m.fils));
      expect(
        r.entries.map((e) => e.id).toList(),
        inside.map((m) => m.id).toList(),
      );
      final byCat = <int, int>{};
      for (final m in inside) {
        byCat[m.cat] = (byCat[m.cat] ?? 0) + m.fils;
      }
      expect({for (final c in r.byCategory) c.categoryId: c.totalFils}, byCat);
      expect(r.byCategory.fold<int>(0, (s, c) => s + c.count), r.count);
    }

    // 300 random periods of every kind.
    final first = LocalDate(2027, 11, 13);
    for (var i = 0; i < 300; i++) {
      final d = first.addDays(rnd.nextInt(510));
      verify(ReportPeriod.of(ReportKind.values[i % 3], d));
    }

    // Partitions: all months, and all weeks, add up to the grand total.
    final grand = model.values.fold<int>(0, (s, m) => s + m.fils);
    var monthSum = 0, monthCount = 0;
    for (
      var p = ReportPeriod.monthly(first);
      !p.start.isAfter(LocalDate(2029, 4, 30));
      p = p.shift(1)
    ) {
      final r = t.expenses.report(p);
      monthSum += r.totalFils;
      monthCount += r.count;
    }
    var weekSum = 0;
    for (
      var p = ReportPeriod.weekly(first);
      !p.start.isAfter(LocalDate(2029, 4, 30));
      p = p.shift(1)
    ) {
      weekSum += t.expenses.report(p).totalFils;
    }
    expect(monthSum, grand);
    expect(monthCount, model.length);
    expect(weekSum, grand);
    expect(t.expenses.count(), model.length);

    // Survives a restart unchanged.
    t.reopen();
    verify(ReportPeriod.monthly(LocalDate(2028, 2, 29)));
    t.dispose();
  });
}
