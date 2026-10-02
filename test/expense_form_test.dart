import 'dart:async';

import 'package:daily_expense_tracker/core/local_date.dart';
import 'package:daily_expense_tracker/state/app_session.dart';
import 'package:daily_expense_tracker/state/expense_form_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';
import 'helpers.dart';

void main() {
  late TestDb t;
  late FakePlatform platform;
  late FixedClock clock;
  late AppSession session;

  setUp(() {
    t = TestDb.create();
    platform = FakePlatform();
    clock = FixedClock(DateTime(2026, 10, 2, 14, 5, 30));
    session = AppSession(
      db: t.db,
      platform: platform,
      clock: clock,
      dataDirPath: t.dir.path,
    );
  });
  tearDown(() => t.dispose());

  ExpenseFormController filled() {
    final c = ExpenseFormController(session)
      ..selectCategory(t.category('Food').id)
      ..amount.text = '25'
      ..remarks.text = 'lunch';
    return c;
  }

  test('rapid repeated Save taps create exactly one record', () async {
    final c = filled();
    platform.freeBytesGate =
        Completer<void>(); // hold the first save mid-flight
    final first = c.submit();
    final second = c.submit();
    final third = c.submit();
    expect(c.isSaving, isTrue);
    expect(await second, SaveOutcome.ignoredBusy);
    expect(await third, SaveOutcome.ignoredBusy);
    platform.freeBytesGate!.complete();
    expect(await first, SaveOutcome.saved);
    expect(t.expenses.count(), 1);
    expect(c.isSaving, isFalse);
  });

  test(
    'success clears the form; no category is preselected afterwards',
    () async {
      final c = filled();
      expect(await c.submit(), SaveOutcome.saved);
      expect(c.categoryId, isNull);
      expect(c.amount.text, isEmpty);
      expect(c.remarks.text, isEmpty);
    },
  );

  test('timestamp is captured at Save, not when the form opened', () async {
    final c = filled();
    clock.value = DateTime(2026, 10, 2, 18, 45, 10);
    await c.submit();
    final e = t.expenses.recent(limit: 1).single;
    expect(e.captured.localTime, '18:45:10');
    expect(e.localDate, LocalDate(2026, 10, 2));
  });

  test('validation errors keep the form and save nothing', () async {
    final c = ExpenseFormController(session)..amount.text = '0';
    expect(await c.submit(), SaveOutcome.invalid);
    expect(c.errors.category, isNotNull);
    expect(c.errors.amount, isNotNull);
    expect(t.expenses.count(), 0);
  });

  test('low storage fails safely: form kept, nothing written', () async {
    final c = filled();
    platform.free = 1024;
    expect(await c.submit(), SaveOutcome.failed);
    expect(c.failureMessage, contains('storage'));
    expect(c.amount.text, '25');
    expect(t.expenses.count(), 0);
  });

  test(
    'category turned off while the form is open → field error, nothing saved',
    () async {
      final c = filled();
      t.categories.setActive(t.category('Food').id, false, nowUtcMs: 1);
      expect(await c.submit(), SaveOutcome.invalid);
      expect(c.errors.category, contains('no longer available'));
      expect(c.remarks.text, 'lunch');
      expect(t.expenses.count(), 0);
    },
  );

  test(
    'database write failure keeps the form and shows a useful error',
    () async {
      final c = filled();
      t.db.raw.execute('PRAGMA query_only = ON;'); // every write now fails
      expect(await c.submit(), SaveOutcome.failed);
      expect(c.failureMessage, contains('Nothing'));
      expect(c.amount.text, '25');
      expect(c.remarks.text, 'lunch');
      t.db.raw.execute('PRAGMA query_only = OFF;');
      expect(t.expenses.count(), 0);
    },
  );

  test(
    'editing keeps a deactivated category and the original capture time',
    () async {
      final add = filled();
      await add.submit();
      final saved = t.expenses.recent(limit: 1).single;
      t.categories.setActive(saved.categoryId, false, nowUtcMs: 2);

      clock.value = DateTime(2026, 10, 9, 9, 0);
      final edit = ExpenseFormController(
        session,
        existing: t.expenses.byId(saved.id),
      );
      expect(edit.selectableCategories().first.id, saved.categoryId);
      expect(edit.selectableCategories().where((c) => !c.isActive).length, 1);
      edit.amount.text = '30.75';
      expect(await edit.submit(), SaveOutcome.saved);
      final after = t.expenses.byId(saved.id)!;
      expect(after.amountFils, 3075);
      expect(after.captured.instantUtcMs, saved.captured.instantUtcMs);
      expect(after.localDate, LocalDate(2026, 10, 2));
    },
  );

  test('delete removes the record and bumps the data revision', () async {
    await filled().submit();
    final e = t.expenses.recent(limit: 1).single;
    final before = session.revision.value;
    final c = ExpenseFormController(session, existing: e);
    expect(await c.delete(), isTrue);
    expect(t.expenses.count(), 0);
    expect(session.revision.value, greaterThan(before));
  });
}
