import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:daily_expense_tracker/core/local_date.dart';
import 'package:daily_expense_tracker/data/backup_service.dart';
import 'package:daily_expense_tracker/data/database.dart';
import 'package:daily_expense_tracker/data/expense_repository.dart';
import 'package:daily_expense_tracker/data/failures.dart';
import 'package:daily_expense_tracker/data/meta_repository.dart';
import 'package:daily_expense_tracker/domain/models.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

void main() {
  late TestDb oldPhone;
  late Directory work;
  const password = 'Dubai2026!';

  setUp(() {
    oldPhone = TestDb.create();
    work = Directory.systemTemp.createTempSync('det_backup');
    final food = oldPhone.category('Food');
    final petrol = oldPhone.category('Petrol');
    oldPhone.categories.add('Tolls', nowUtcMs: 1);
    oldPhone.categories.setActive(
      oldPhone.category('Carwash').id,
      false,
      nowUtcMs: 1,
    );
    oldPhone.expenses.insert(
      ExpenseDraft(
        categoryId: petrol.id,
        amountFils: 10000,
        remarks: 'secret-remark-xyz',
      ),
      dubai(2026, 9, 30, 8, 15),
      nowUtcMs: 100,
    );
    oldPhone.expenses.insert(
      ExpenseDraft(categoryId: food.id, amountFils: 2550, remarks: null),
      dubai(2026, 10, 2, 13, 0),
      nowUtcMs: 200,
    );
    MetaRepository(oldPhone.db).write('activation_token', 'OLD-PHONE-TOKEN');
  });
  tearDown(() {
    oldPhone.dispose();
    work.deleteSync(recursive: true);
  });

  String path(String name) => '${work.path}${Platform.pathSeparator}$name';

  test('backup → restore on a new phone keeps every record exactly', () {
    final backup = path('b.$backupFileExtension');
    final info = BackupService(oldPhone.db)
        .createBackup(outPath: backup, password: password, nowUtcMs: 5000);
    expect(info.expenseCount, 2);
    expect(info.totalFils, 12550);
    expect(info.firstDate, LocalDate(2026, 9, 30));
    expect(info.lastDate, LocalDate(2026, 10, 2));
    expect(MetaRepository(oldPhone.db).read(metaLastBackupAt), '5000');

    // New phone: different device key.
    final newKey = randomKey(Random(77));
    final target = path('restored.db');
    BackupService.rebuildForDevice(
      backupPath: backup,
      password: password,
      targetPath: target,
      deviceKey: newKey,
    );
    final restored = AppDatabase.open(path: target, key: newKey, nowUtcMs: 1);
    final a = ExpenseRepository(oldPhone.db).recent(limit: 10);
    final b = ExpenseRepository(restored).recent(limit: 10);
    expect(b.length, a.length);
    for (var i = 0; i < a.length; i++) {
      expect(b[i].id, a[i].id);
      expect(b[i].amountFils, a[i].amountFils);
      expect(b[i].remarks, a[i].remarks);
      expect(b[i].categoryId, a[i].categoryId);
      expect(b[i].captured.instantUtcMs, a[i].captured.instantUtcMs);
      expect(b[i].captured.localTime, a[i].captured.localTime);
      expect(b[i].captured.offsetMinutes, a[i].captured.offsetMinutes);
      expect(b[i].createdAtUtcMs, a[i].createdAtUtcMs);
    }
    final cats = restored.raw.select(
      'SELECT name, is_active FROM categories ORDER BY id',
    );
    expect(cats.map((r) => r['name']), contains('Tolls'));
    expect(cats.firstWhere((r) => r['name'] == 'Carwash')['is_active'], 0);
    // Activation never travels in a backup.
    expect(MetaRepository(restored).read('activation_token'), isNull);
    expect(restored.schemaVersion, oldPhone.db.schemaVersion);
    restored.close();
    // Old phone's key cannot open the restored file.
    expect(
      () => AppDatabase.open(path: target, key: oldPhone.key, nowUtcMs: 1),
      throwsA(isA<AppFailure>()),
    );
  });

  test(
    'backup file is encrypted: no plaintext, not openable without password',
    () {
      final backup = path('b.$backupFileExtension');
      BackupService(oldPhone.db)
          .createBackup(outPath: backup, password: password, nowUtcMs: 1);
      final bytes = File(backup).readAsBytesSync();
      final text = String.fromCharCodes(bytes);
      expect(text.startsWith('SQLite format 3'), isFalse);
      expect(text.contains('secret-remark-xyz'), isFalse);
      expect(text.contains('Petrol'), isFalse);
      expect(text.contains('OLD-PHONE-TOKEN'), isFalse);
    },
  );

  test('wrong password, random file and empty file are refused', () {
    final backup = path('b.$backupFileExtension');
    BackupService(oldPhone.db)
        .createBackup(outPath: backup, password: password, nowUtcMs: 1);
    expect(
      () => BackupService.inspectBackup(backup, 'Dubai2026?'),
      throwsA(
        isA<AppFailure>().having(
          (f) => f.userMessage,
          'msg',
          contains('password is wrong'),
        ),
      ),
    );
    final junk = path('junk.$backupFileExtension');
    File(
      junk,
    ).writeAsBytesSync(Uint8List.fromList(List.generate(9000, (i) => i * 7)));
    expect(
      () => BackupService.inspectBackup(junk, password),
      throwsA(isA<AppFailure>()),
    );
    final empty = path('empty.$backupFileExtension');
    File(empty).writeAsBytesSync([]);
    expect(
      () => BackupService.inspectBackup(empty, password),
      throwsA(isA<AppFailure>()),
    );
    // The device's own database is not a backup, even with its key.
    oldPhone.db.close();
    expect(
      () => BackupService.inspectBackup(oldPhone.path, password),
      throwsA(isA<AppFailure>()),
    );
    oldPhone.db = AppDatabase.open(
      path: oldPhone.path,
      key: oldPhone.key,
      nowUtcMs: 1,
    );
  });

  test('tampered backup is detected, never half-restored', () {
    for (var i = 0; i < 200; i++) {
      oldPhone.expenses.insert(
        ExpenseDraft(
          categoryId: oldPhone.category('Food').id,
          amountFils: 100 + i,
          remarks: 'r$i',
        ),
        dubai(2026, 10, 1),
        nowUtcMs: 1,
      );
    }
    final backup = path('b.$backupFileExtension');
    BackupService(oldPhone.db)
        .createBackup(outPath: backup, password: password, nowUtcMs: 1);
    final bytes = File(backup).readAsBytesSync();
    bytes[bytes.length - 3000] ^= 0x10;
    File(backup).writeAsBytesSync(bytes);
    final target = path('restored.db');
    expect(
      () => BackupService.rebuildForDevice(
        backupPath: backup,
        password: password,
        targetPath: target,
        deviceKey: randomKey(),
      ),
      throwsA(isA<AppFailure>()),
    );
    expect(File(target).existsSync(), isFalse);
  });

  test('password rules: at least 8 characters, typed twice the same', () {
    expect(validateBackupPassword('1234567', '1234567'), isNotNull);
    expect(validateBackupPassword('12345678', '12345679'), isNotNull);
    expect(validateBackupPassword('12345678', '12345678'), isNull);
    expect(validateBackupPassword("it's 8 ok", "it's 8 ok"), isNull);
    expect(
      () =>
          BackupService(oldPhone.db)
              .createBackup(outPath: path('x'), password: 'short', nowUtcMs: 1),
      throwsA(isA<AppFailure>()),
    );
  });

  test('passwords with quotes and Arabic text work', () {
    for (final pw in [
      "O'Brien''s \"pass\"",
      'كلمة السر ٢٠٢٦',
      r'a$b\c;--DROP',
    ]) {
      final backup = path('p${pw.hashCode}.$backupFileExtension');
      BackupService(oldPhone.db)
          .createBackup(outPath: backup, password: pw, nowUtcMs: 1);
      expect(BackupService.inspectBackup(backup, pw).expenseCount, 2);
    }
  });

  test('empty-data backup restores fine', () {
    final fresh = TestDb.create();
    final backup = path('empty.$backupFileExtension');
    final info = BackupService(fresh.db)
        .createBackup(outPath: backup, password: password, nowUtcMs: 1);
    expect(info.expenseCount, 0);
    expect(info.firstDate, isNull);
    fresh.dispose();
  });

  group('monthly reminder', () {
    const day = 24 * 60 * 60 * 1000;
    bool remind({
      int count = 5,
      int? last,
      int? first,
      int? snooze,
      required int now,
    }) => shouldRemindBackup(
      expenseCount: count,
      lastBackupUtcMs: last,
      firstExpenseCreatedUtcMs: first,
      snoozedUntilUtcMs: snooze,
      nowUtcMs: now,
    );

    test(
      'no records → never',
      () => expect(remind(count: 0, first: 0, now: 100 * day), isFalse),
    );
    test('never backed up: after 30 days of use', () {
      expect(remind(first: 0, now: 29 * day), isFalse);
      expect(remind(first: 0, now: 30 * day), isTrue);
    });
    test('backed up: 30 days after the last backup', () {
      expect(remind(first: 0, last: 50 * day, now: 79 * day), isFalse);
      expect(remind(first: 0, last: 50 * day, now: 80 * day), isTrue);
    });
    test('snooze hides it until the snooze ends', () {
      expect(remind(first: 0, snooze: 40 * day, now: 35 * day), isFalse);
      expect(remind(first: 0, snooze: 40 * day, now: 40 * day), isTrue);
    });
  });
}
