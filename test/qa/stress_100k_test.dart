@Tags(['perf'])
library;

import 'dart:io';
import 'dart:math';

import 'package:daily_expense_tracker/core/capture.dart';
import 'package:daily_expense_tracker/core/local_date.dart';
import 'package:daily_expense_tracker/data/expense_repository.dart';
import 'package:daily_expense_tracker/domain/models.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';

/// QA volume stress: 100,000 expenses (~10 years at 27/day) in the real
/// SQLCipher database. Writes build/stress_100k_report.txt.
void main() {
  test('100,000 expenses: size, speed, full paging, integrity', () {
    final t = TestDb.create();
    final rnd = Random(100000);
    for (var i = 0; i < 40; i++) {
      t.categories.add('Stress category $i', nowUtcMs: 1);
    }
    final cats = t.categories.active();
    final start = DateTime.utc(2017, 1, 1, 4).millisecondsSinceEpoch;
    final sw = Stopwatch()..start();
    var total = 0;
    t.db.transaction(() {
      for (var i = 0; i < 100000; i++) {
        final cat = cats[rnd.nextInt(cats.length)];
        final fils = 100 + rnd.nextInt(500000);
        total += fils;
        t.expenses.insert(
          ExpenseDraft(
            categoryId: cat.id,
            amountFils: fils,
            remarks: cat.requiresRemark || rnd.nextBool()
                ? 'Site ${rnd.nextInt(500)} – vehicle D ${10000 + rnd.nextInt(89999)}'
                : null,
          ),
          CaptureStamp.fromUtcAndOffset(
            start + i * 3150000 + rnd.nextInt(600000),
            240,
            'GST',
          ),
          nowUtcMs: 1,
        );
      }
    });
    final insertMs = sw.elapsedMilliseconds;

    final openSw = Stopwatch()..start();
    t.reopen();
    final openMs = openSw.elapsedMilliseconds;
    final size = File(t.path).lengthSync();

    int timeUs(void Function() f) {
      final s = Stopwatch()..start();
      for (var i = 0; i < 5; i++) {
        f();
      }
      return s.elapsedMicroseconds ~/ 5;
    }

    final last = t.expenses.recent(limit: 1).single.localDate;
    late ReportData month;
    final monthUs = timeUs(
      () => month = t.expenses.report(ReportPeriod.monthly(last)),
    );
    final weekUs = timeUs(() => t.expenses.report(ReportPeriod.weekly(last)));
    final dayUs = timeUs(() => t.expenses.report(ReportPeriod.daily(last)));
    final homeUs = timeUs(() {
      t.expenses.summaryFor(last);
      t.expenses.recent(limit: 40);
    });
    final oldMonthUs = timeUs(
      () => t.expenses.report(ReportPeriod.monthly(LocalDate(2018, 6, 1))),
    );

    // Page through every record the way Home's "Show older" does.
    final pageSw = Stopwatch()..start();
    var seen = 0, pages = 0, sum = 0;
    final ids = <String>{};
    ExpenseCursor? cursor;
    while (true) {
      final page = t.expenses.recent(limit: 40, after: cursor);
      if (page.isEmpty) break;
      pages++;
      for (final e in page) {
        seen++;
        sum += e.amountFils;
        ids.add(e.id);
      }
      cursor = ExpenseCursor(page.last.captured.instantUtcMs, page.last.id);
    }
    final pageAllMs = pageSw.elapsedMilliseconds;
    expect(seen, 100000);
    expect(ids.length, 100000);
    expect(sum, total);

    final integrity = t.db.raw
        .select('PRAGMA integrity_check;')
        .first
        .values
        .first;
    expect(integrity, 'ok');

    final report =
        '''
Daily Expense Tracker — 100,000-record stress (host machine, not a phone)
Date: ${DateTime.now().toIso8601String()}
Host: ${Platform.operatingSystem} ${Platform.operatingSystemVersion}
Records: 100000 across ${cats.length} categories, ~10 years
Database file: $size bytes (${(size / 1048576).toStringAsFixed(1)} MB), ${(size / 100000).toStringAsFixed(0)} bytes/expense
Bulk insert (one transaction): $insertMs ms
Open + key + migration check: $openMs ms
Monthly report, latest month (${month.count} entries): ${(monthUs / 1000).toStringAsFixed(1)} ms
Monthly report, 2018: ${(oldMonthUs / 1000).toStringAsFixed(1)} ms
Weekly report: ${(weekUs / 1000).toStringAsFixed(1)} ms
Daily report: ${(dayUs / 1000).toStringAsFixed(1)} ms
Home (today total + 40 newest): ${(homeUs / 1000).toStringAsFixed(1)} ms
Page through all 100,000 in pages of 40 ($pages pages): $pageAllMs ms (${(pageAllMs / pages).toStringAsFixed(2)} ms/page)
Grand total check: exact (${(total / 100).toStringAsFixed(2)} AED); integrity_check: $integrity
''';
    Directory('build').createSync();
    File('build/stress_100k_report.txt').writeAsStringSync(report);
    // ignore: avoid_print
    print(report);
    expect(monthUs, lessThan(250000));
    expect(homeUs, lessThan(50000));
    t.dispose();
  });
}
