import 'dart:io';

import 'package:daily_expense_tracker/core/capture.dart';
import 'package:daily_expense_tracker/core/local_date.dart';
import 'package:daily_expense_tracker/data/database.dart';
import 'package:daily_expense_tracker/data/expense_repository.dart';
import 'package:daily_expense_tracker/data/failures.dart';
import 'package:daily_expense_tracker/data/migrations.dart';
import 'package:daily_expense_tracker/domain/models.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

void main() {
  late TestDb t;
  setUp(() => t = TestDb.create());
  tearDown(() => t.dispose());

  ExpenseDraft draft(String cat, int fils, [String? remarks]) => ExpenseDraft(
    categoryId: t.category(cat).id,
    amountFils: fils,
    remarks: remarks,
  );

  group('encryption', () {
    test('database is SQLCipher-encrypted and unreadable without the key', () {
      expect(t.db.cipherVersion(), isNotEmpty);
      t.expenses.insert(
        draft('Food', 2500, 'lunch-secret-marker'),
        dubai(2026, 10, 2),
        nowUtcMs: 1,
      );
      t.db.close();

      final bytes = File(t.path).readAsBytesSync();
      expect(
        String.fromCharCodes(bytes.take(16)),
        isNot(startsWith('SQLite format 3')),
      );
      expect(
        String.fromCharCodes(bytes).contains('lunch-secret-marker'),
        isFalse,
      );
      expect(String.fromCharCodes(bytes).contains('Petrol'), isFalse);

      expect(
        () => AppDatabase.open(path: t.path, key: randomKey(), nowUtcMs: 0),
        throwsA(
          isA<AppFailure>().having(
            (f) => f.kind,
            'kind',
            FailureKind.wrongKeyOrCorrupt,
          ),
        ),
      );
      t.db = AppDatabase.open(path: t.path, key: t.key, nowUtcMs: 0);
      expect(t.expenses.count(), 1);
    });
  });

  group('categories', () {
    test('seeded once with the 8 defaults; Other requires a remark', () {
      final names = t.categories.all().map((c) => c.name).toList();
      expect(names, [
        'Petrol', 'Food', 'Labor', 'Salik', 'Carwash', //
        'Vehicle Maintenance', 'Car Parking Fee', 'Other',
      ]);
      expect(t.category('Other').requiresRemark, isTrue);
      expect(t.category('Food').requiresRemark, isFalse);

      // Rename + deactivate, then restart: defaults are NOT re-seeded.
      t.categories.rename(t.category('Food').id, 'Meals', nowUtcMs: 2);
      t.categories.setActive(t.category('Salik').id, false, nowUtcMs: 2);
      t.reopen();
      expect(t.categories.all().length, 8);
      expect(t.categories.all().any((c) => c.name == 'Food'), isFalse);
      expect(t.db.schemaVersion, latestSchemaVersion);
    });

    test('rejects empty and duplicate names ignoring case and spaces', () {
      expect(
        () => t.categories.add('   ', nowUtcMs: 1),
        throwsA(isA<AppFailure>()),
      );
      expect(
        () => t.categories.add('  petrol ', nowUtcMs: 1),
        throwsA(isA<AppFailure>()),
      );
      expect(
        () => t.categories.add('CAR   PARKING fee', nowUtcMs: 1),
        throwsA(isA<AppFailure>()),
      );
      final c = t.categories.add('  Tolls  ', nowUtcMs: 1);
      expect(c.name, 'Tolls');
      expect(
        () => t.categories.add('tolls', nowUtcMs: 1),
        throwsA(isA<AppFailure>()),
      );
      expect(
        () => t.categories.rename(c.id, 'FOOD', nowUtcMs: 1),
        throwsA(isA<AppFailure>()),
      );
      // Changing only the case of its own name is allowed.
      expect(t.categories.rename(c.id, 'TOLLS', nowUtcMs: 1).name, 'TOLLS');
    });

    test('duplicate check also covers deactivated categories', () {
      t.categories.setActive(t.category('Carwash').id, false, nowUtcMs: 1);
      expect(
        () => t.categories.add('carwash', nowUtcMs: 1),
        throwsA(
          isA<AppFailure>().having(
            (f) => f.userMessage,
            'msg',
            contains('turned off'),
          ),
        ),
      );
    });

    test(
      'deactivated category: not selectable for new expenses, history intact',
      () {
        final petrol = t.category('Petrol');
        final old = t.expenses.insert(
          draft('Petrol', 5000),
          dubai(2026, 9, 1),
          nowUtcMs: 1,
        );
        t.categories.setActive(petrol.id, false, nowUtcMs: 2);

        expect(t.categories.active().any((c) => c.id == petrol.id), isFalse);
        expect(
          () => t.expenses.insert(
            ExpenseDraft(categoryId: petrol.id, amountFils: 100, remarks: null),
            dubai(2026, 9, 2),
            nowUtcMs: 3,
          ),
          throwsA(
            isA<AppFailure>().having(
              (f) => f.kind,
              'kind',
              FailureKind.categoryInactive,
            ),
          ),
        );

        // Old entry still opens, shows its category and accepts non-category edits.
        final reopened = t.expenses.byId(old.id)!;
        expect(reopened.currentCategoryName, 'Petrol');
        expect(reopened.categoryIsActive, isFalse);
        final edited = t.expenses.update(
          old.id,
          ExpenseDraft(
            categoryId: petrol.id,
            amountFils: 5500,
            remarks: 'corrected',
          ),
          nowUtcMs: 4,
        );
        expect(edited.amountFils, 5500);
        expect(edited.categoryId, petrol.id);

        // …and it still appears in reports, grouped by its stable id.
        final r = t.expenses.report(
          ReportPeriod.monthly(LocalDate(2026, 9, 1)),
        );
        expect(r.byCategory.single.categoryId, petrol.id);
        expect(r.byCategory.single.isActive, isFalse);
      },
    );

    test('renaming keeps the snapshot and groups by stable id', () {
      final food = t.category('Food');
      final e = t.expenses.insert(
        draft('Food', 1000),
        dubai(2026, 10, 1),
        nowUtcMs: 1,
      );
      t.categories.rename(food.id, 'Meals', nowUtcMs: 2);
      final again = t.expenses.byId(e.id)!;
      expect(again.categoryLabelSnapshot, 'Food');
      expect(again.currentCategoryName, 'Meals');
      final r = t.expenses.report(ReportPeriod.daily(LocalDate(2026, 10, 1)));
      expect(r.byCategory.single.name, 'Meals');
      expect(r.byCategory.single.categoryId, food.id);
    });
  });

  group('expenses', () {
    test('AED 100 + 25 + 8 = AED 133, count 3, correct category totals', () {
      t.expenses.insert(
        draft('Petrol', 10000),
        dubai(2026, 10, 2, 8),
        nowUtcMs: 1,
      );
      t.expenses.insert(
        draft('Food', 2500),
        dubai(2026, 10, 2, 13),
        nowUtcMs: 1,
      );
      t.expenses.insert(
        draft('Salik', 800),
        dubai(2026, 10, 2, 18),
        nowUtcMs: 1,
      );

      final r = t.expenses.report(ReportPeriod.daily(LocalDate(2026, 10, 2)));
      expect(r.totalFils, 13300);
      expect(r.count, 3);
      final byName = {for (final c in r.byCategory) c.name: c.totalFils};
      expect(byName, {'Petrol': 10000, 'Food': 2500, 'Salik': 800});
      // Newest first.
      expect(r.entries.map((e) => e.amountFils), [800, 2500, 10000]);

      final s = t.expenses.summaryFor(LocalDate(2026, 10, 2));
      expect((s.count, s.totalFils), (3, 13300));
    });

    test(
      'ids, timestamps and capture fields are stored and survive restart',
      () {
        final stamp = dubai(2026, 10, 2, 14, 5);
        final e = t.expenses.insert(
          draft('Food', 1234, 'tea'),
          stamp,
          nowUtcMs: 777,
        );
        expect(
          e.id,
          matches(
            RegExp(
              r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
            ),
          ),
        );
        t.reopen();
        final back = t.expenses.byId(e.id)!;
        expect(back.captured.instantUtcMs, stamp.instantUtcMs);
        expect(back.captured.offsetMinutes, 240);
        expect(back.captured.timeZoneName, 'GST');
        expect(back.captured.localDate, LocalDate(2026, 10, 2));
        expect(back.captured.localTime, '14:05:00');
        expect(back.createdAtUtcMs, 777);
        expect(back.updatedAtUtcMs, 777);
        expect(back.remarks, 'tea');
      },
    );

    test('edit changes description/amount/remarks but never capture time', () {
      final stamp = dubai(2026, 10, 2, 9, 30);
      final e = t.expenses.insert(draft('Food', 1000), stamp, nowUtcMs: 100);
      final edited = t.expenses.update(
        e.id,
        draft('Labor', 4550, 'helper'),
        nowUtcMs: 200,
      );
      expect(edited.amountFils, 4550);
      expect(edited.currentCategoryName, 'Labor');
      expect(edited.categoryLabelSnapshot, 'Labor');
      expect(edited.remarks, 'helper');
      expect(edited.captured.instantUtcMs, stamp.instantUtcMs);
      expect(edited.captured.localTime, '09:30:00');
      expect(edited.createdAtUtcMs, 100);
      expect(edited.updatedAtUtcMs, 200);

      final r = t.expenses.report(ReportPeriod.daily(LocalDate(2026, 10, 2)));
      expect(r.totalFils, 4550);
      expect(r.byCategory.single.name, 'Labor');
    });

    test('delete removes permanently and totals update immediately', () {
      final a = t.expenses.insert(
        draft('Food', 1000),
        dubai(2026, 10, 2),
        nowUtcMs: 1,
      );
      t.expenses.insert(draft('Food', 500), dubai(2026, 10, 2), nowUtcMs: 1);
      expect(t.expenses.delete(a.id), isTrue);
      expect(t.expenses.byId(a.id), isNull);
      expect(t.expenses.delete(a.id), isFalse);
      expect(t.expenses.summaryFor(LocalDate(2026, 10, 2)).totalFils, 500);
      t.reopen();
      expect(t.expenses.count(), 1);
    });

    test(
      'database rejects invalid amounts even if UI validation is bypassed',
      () {
        for (final bad in [0, -1, 100000000]) {
          expect(
            () => t.expenses.insert(
              ExpenseDraft(
                categoryId: t.category('Food').id,
                amountFils: bad,
                remarks: null,
              ),
              dubai(2026, 10, 2),
              nowUtcMs: 1,
            ),
            throwsA(isA<AppFailure>()),
          );
        }
        expect(t.expenses.count(), 0);
      },
    );

    test('travel does not move past entries to another day', () {
      // 23:30 in Dubai on 2 Oct = 19:30 UTC; in London (GMT+1) it would be
      // 20:30 on 2 Oct, and in Tokyo (GMT+9) 04:30 on 3 Oct.
      final e = t.expenses.insert(
        draft('Food', 100),
        dubai(2026, 10, 2, 23, 30),
        nowUtcMs: 1,
      );
      expect(e.localDate, LocalDate(2026, 10, 2));
      final tokyoCapture = CaptureStamp.fromUtcAndOffset(
        e.captured.instantUtcMs,
        540,
        'JST',
      );
      expect(tokyoCapture.localDate, LocalDate(2026, 10, 3)); // would differ…
      // …but the stored capture date is what reports use.
      expect(
        t.expenses.report(ReportPeriod.daily(LocalDate(2026, 10, 2))).count,
        1,
      );
      expect(
        t.expenses.report(ReportPeriod.daily(LocalDate(2026, 10, 3))).count,
        0,
      );
    });

    test('recent() pages newest first without gaps or duplicates', () {
      for (var i = 0; i < 25; i++) {
        t.expenses.insert(
          draft('Food', 100 + i),
          dubai(2026, 10, 1, 8, i),
          nowUtcMs: 1,
        );
      }
      final seen = <String>[];
      ExpenseCursor? cursor;
      while (true) {
        final page = t.expenses.recent(limit: 10, after: cursor);
        if (page.isEmpty) break;
        seen.addAll(page.map((e) => e.id));
        cursor = ExpenseCursor(page.last.captured.instantUtcMs, page.last.id);
      }
      expect(seen.length, 25);
      expect(seen.toSet().length, 25);
      expect(t.expenses.recent(limit: 1).single.amountFils, 124);
    });
  });

  test('newer schema version is refused and the file is left untouched', () {
    t.db.raw.userVersion = latestSchemaVersion + 1;
    t.db.close();
    final before = File(t.path).readAsBytesSync();
    expect(
      () => AppDatabase.open(path: t.path, key: t.key, nowUtcMs: 0),
      throwsA(
        isA<AppFailure>().having(
          (f) => f.kind,
          'kind',
          FailureKind.newerSchema,
        ),
      ),
    );
    expect(File(t.path).readAsBytesSync(), before);
    // Put a fresh db in place so tearDown has something to close.
    File(t.path).deleteSync();
    t.db = AppDatabase.open(path: t.path, key: t.key, nowUtcMs: 0);
  });
}
