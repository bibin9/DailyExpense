@Tags(['perf'])
library;

import 'dart:io';
import 'dart:math';

import 'package:daily_expense_tracker/core/capture.dart';
import 'package:daily_expense_tracker/core/local_date.dart';
import 'package:daily_expense_tracker/domain/models.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

/// Measures database size and query time for 10,000 representative
/// expenses (~27 a day for a year) in the real SQLCipher database.
/// Host-machine numbers; repeat on the agreed phones (docs/TEST_REPORT.md).
void main() {
  test('10,000 expenses: size and report speed', () {
    final t = TestDb.create();
    final rnd = Random(2026);
    final cats = t.categories.active();
    const remarks = [
      null,
      null,
      'Dubai Marina site',
      'Vehicle D 12345 – oil change',
      'Lunch for 3 workers',
      'Parking near JLT tower',
      'Salik Al Garhoud',
      'Helper overtime, villa 14',
      'Carwash before client visit',
    ];
    final start = DateTime.utc(2025, 10, 1, 4); // 08:00 Dubai
    final sw = Stopwatch()..start();
    t.db.transaction(() {
      for (var i = 0; i < 10000; i++) {
        final at = start.add(Duration(minutes: i * 52 + rnd.nextInt(30)));
        final cat = cats[rnd.nextInt(cats.length)];
        t.expenses.insert(
          ExpenseDraft(
            categoryId: cat.id,
            amountFils: 100 + rnd.nextInt(200000),
            remarks: cat.requiresRemark
                ? 'Misc purchase #$i'
                : remarks[rnd.nextInt(remarks.length)],
          ),
          CaptureStamp.fromUtcAndOffset(at.millisecondsSinceEpoch, 240, 'GST'),
          nowUtcMs: at.millisecondsSinceEpoch,
        );
      }
    });
    final insertMs = sw.elapsedMilliseconds;
    expect(t.expenses.count(), 10000);
    t.reopen();
    final size = File(t.path).lengthSync();

    final lastDay = LocalDate.parse(
      t.expenses.recent(limit: 1).single.localDate.toIso(),
    );
    int time(void Function() f, [int runs = 5]) {
      final s = Stopwatch()..start();
      for (var i = 0; i < runs; i++) {
        f();
      }
      return s.elapsedMicroseconds ~/ runs;
    }

    late ReportData month;
    final monthUs = time(
      () => month = t.expenses.report(ReportPeriod.monthly(lastDay)),
    );
    final weekUs = time(() => t.expenses.report(ReportPeriod.weekly(lastDay)));
    final dayUs = time(() => t.expenses.report(ReportPeriod.daily(lastDay)));
    final homeUs = time(() {
      t.expenses.summaryFor(lastDay);
      t.expenses.recent(limit: 40);
    });
    final openSw = Stopwatch()..start();
    t.reopen();
    final openMs = openSw.elapsedMilliseconds;

    final report =
        '''
Daily Expense Tracker — storage/performance measurement (host machine)
Date: ${DateTime.now().toIso8601String()}
Host: ${Platform.operatingSystem} ${Platform.operatingSystemVersion}
Records: 10000 (encrypted SQLCipher, schema v${t.db.schemaVersion}, cipher ${t.db.cipherVersion()})
Database file size: $size bytes (${(size / 1024 / 1024).toStringAsFixed(2)} MB)
Bytes per expense (incl. indexes, overhead): ${(size / 10000).toStringAsFixed(0)}
Bulk insert of 10000 (one transaction): $insertMs ms
Open + key + migration check: $openMs ms
Monthly report (${month.count} entries): ${(monthUs / 1000).toStringAsFixed(1)} ms
Weekly report: ${(weekUs / 1000).toStringAsFixed(1)} ms
Daily report: ${(dayUs / 1000).toStringAsFixed(1)} ms
Home (today total + 40 newest): ${(homeUs / 1000).toStringAsFixed(1)} ms
''';
    Directory('build').createSync();
    File('build/perf_report.txt').writeAsStringSync(report);
    // ignore: avoid_print
    print(report);

    expect(size, lessThan(20 * 1024 * 1024));
    expect(
      monthUs,
      lessThan(500000),
    ); // generous host bound; phones measured separately
    t.dispose();
  });
}
