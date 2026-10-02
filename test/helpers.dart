import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:daily_expense_tracker/core/capture.dart';
import 'package:daily_expense_tracker/data/category_repository.dart';
import 'package:daily_expense_tracker/data/database.dart';
import 'package:daily_expense_tracker/data/expense_repository.dart';
import 'package:daily_expense_tracker/domain/models.dart';

Uint8List randomKey([Random? r]) {
  final rnd = r ?? Random.secure();
  return Uint8List.fromList(List.generate(32, (_) => rnd.nextInt(256)));
}

class TestDb {
  TestDb._(this.dir, this.key, this.db);

  final Directory dir;
  final Uint8List key;
  AppDatabase db;

  String get path =>
      '${dir.path}${Platform.pathSeparator}${AppDatabase.fileName}';

  static TestDb create() {
    final dir = Directory.systemTemp.createTempSync('det_test');
    final key = randomKey();
    final db = AppDatabase.open(
      path: '${dir.path}${Platform.pathSeparator}${AppDatabase.fileName}',
      key: key,
      nowUtcMs: 0,
    );
    return TestDb._(dir, key, db);
  }

  CategoryRepository get categories => CategoryRepository(db);
  ExpenseRepository get expenses => ExpenseRepository(db);

  /// Simulates an app restart: close and reopen with the same key.
  void reopen() {
    db.close();
    db = AppDatabase.open(path: path, key: key, nowUtcMs: 1);
  }

  void dispose() {
    db.close();
    dir.deleteSync(recursive: true);
  }

  Category category(String name) =>
      categories.all().firstWhere((c) => c.name == name);
}

/// Dubai (GMT+4) capture at the given local wall-clock time.
CaptureStamp dubai(int y, int m, int d, [int h = 12, int min = 0]) =>
    CaptureStamp.fromUtcAndOffset(
      DateTime.utc(
        y,
        m,
        d,
        h,
        min,
      ).subtract(const Duration(hours: 4)).millisecondsSinceEpoch,
      240,
      'GST',
    );
