import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:daily_expense_tracker/data/database.dart';
import 'package:daily_expense_tracker/data/failures.dart';
import 'package:daily_expense_tracker/domain/models.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';

/// QA: damaged files, full disk and failed transactions must fail safely —
/// no crash, no silent data loss, no overwriting of the user's file.
void main() {
  late TestDb t;
  setUp(() => t = TestDb.create());
  tearDown(() {
    try {
      t.dispose();
    } on Object {
      t.dir.deleteSync(recursive: true);
    }
  });

  ExpenseDraft food(int fils) => ExpenseDraft(
    categoryId: t.category('Food').id,
    amountFils: fils,
    remarks: null,
  );

  void expectSafeOpenFailure(Uint8List damaged) {
    t.db.close();
    File(t.path).writeAsBytesSync(damaged);
    expect(
      () => AppDatabase.open(path: t.path, key: t.key, nowUtcMs: 0),
      throwsA(isA<AppFailure>()),
    );
    // The damaged file is left exactly as it was (never overwritten/reset).
    expect(File(t.path).readAsBytesSync(), damaged);
    // Re-create so tearDown can close it.
    File(t.path).deleteSync();
    t.db = AppDatabase.open(path: t.path, key: t.key, nowUtcMs: 0);
  }

  test('garbage file is refused safely', () {
    final rnd = Random(1);
    expectSafeOpenFailure(
      Uint8List.fromList(List.generate(8192, (_) => rnd.nextInt(256))),
    );
  });

  test('truncated database is refused safely', () {
    for (var i = 0; i < 50; i++) {
      t.expenses.insert(food(100 + i), dubai(2026, 10, 2), nowUtcMs: 1);
    }
    t.db.close();
    final bytes = File(t.path).readAsBytesSync();
    t.db = AppDatabase.open(path: t.path, key: t.key, nowUtcMs: 0);
    expectSafeOpenFailure(Uint8List.sublistView(bytes, 0, bytes.length ~/ 3));
  });

  test(
    'single flipped byte in a data page is detected (HMAC), not silently read',
    () {
      for (var i = 0; i < 200; i++) {
        t.expenses.insert(food(100 + i), dubai(2026, 10, 2), nowUtcMs: 1);
      }
      t.db.close();
      final bytes = File(t.path).readAsBytesSync();
      bytes[bytes.length - 2000] ^= 0x40;
      File(t.path).writeAsBytesSync(bytes);
      var detected = false;
      try {
        final db = AppDatabase.open(path: t.path, key: t.key, nowUtcMs: 0);
        try {
          // Reads every page; SQLCipher's per-page HMAC must flag the change.
          final quick = db.raw.select('PRAGMA quick_check;');
          final cipher = db.raw.select('PRAGMA cipher_integrity_check;');
          detected = quick.first.values.first != 'ok' || cipher.isNotEmpty;
        } on Object {
          detected = true;
        }
        db.close();
      } on AppFailure {
        detected = true;
      }
      expect(detected, isTrue);
      File(t.path).deleteSync();
      t.db = AppDatabase.open(path: t.path, key: t.key, nowUtcMs: 0);
    },
  );

  test('disk full: write fails with storage message, earlier data intact', () {
    t.expenses.insert(food(4200), dubai(2026, 10, 1), nowUtcMs: 1);
    final pages =
        t.db.raw.select('PRAGMA page_count;').first.values.first as int;
    t.db.raw.execute('PRAGMA max_page_count = $pages;'); // simulate full disk
    AppFailure? failure;
    var saved = 0;
    try {
      for (var i = 0; i < 5000; i++) {
        t.expenses.insert(
          ExpenseDraft(
            categoryId: t.category('Other').id,
            amountFils: 1,
            remarks: 'x' * 200,
          ),
          dubai(2026, 10, 2),
          nowUtcMs: 2,
        );
        saved++;
      }
    } on AppFailure catch (f) {
      failure = f;
    }
    expect(failure?.kind, FailureKind.storageFull);
    expect(failure!.userMessage, contains('Nothing was saved'));
    // Earlier record and every committed record still there and consistent.
    expect(t.expenses.count(), 1 + saved);
    expect(t.expenses.summaryFor(dubai(2026, 10, 1).localDate).totalFils, 4200);
    expect(t.db.raw.select('PRAGMA integrity_check;').first.values.first, 'ok');
    // After space is freed the app continues normally.
    t.db.raw.execute('PRAGMA max_page_count = 1073741823;');
    t.expenses.insert(food(1), dubai(2026, 10, 3), nowUtcMs: 3);
    expect(t.expenses.count(), 2 + saved);
  });

  test('failure inside a transaction rolls back completely', () {
    t.expenses.insert(food(100), dubai(2026, 10, 2), nowUtcMs: 1);
    expect(
      () => t.db.transaction(() {
        t.db.raw.execute("UPDATE expenses SET amount_fils = 999;");
        throw StateError('power cut');
      }),
      throwsStateError,
    );
    expect(t.expenses.recent(limit: 1).single.amountFils, 100);
    expect(t.db.raw.autocommit, isTrue);
  });

  test('100 open/close cycles keep data and integrity', () {
    for (var i = 0; i < 100; i++) {
      t.expenses.insert(food(i + 1), dubai(2026, 10, 2), nowUtcMs: i);
      t.reopen();
    }
    expect(t.expenses.count(), 100);
    expect(t.expenses.summaryFor(dubai(2026, 10, 2).localDate).totalFils, 5050);
    expect(t.db.raw.select('PRAGMA integrity_check;').first.values.first, 'ok');
    expect(t.db.raw.select('PRAGMA cipher_integrity_check;'), isEmpty);
  });
}
