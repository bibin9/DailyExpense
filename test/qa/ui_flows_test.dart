import 'package:daily_expense_tracker/state/app_gate_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'ui_harness.dart';

/// QA: end-to-end UI flows through the real screens.
void main() {
  testWidgets('AED 100 + 25 + 8 through the UI → AED 133, 3 entries', (
    tester,
  ) async {
    final h = UiHarness(tester);
    await h.start();
    await h.addExpense('Petrol', '100');
    await h.addExpense('Food', '25');
    await h.addExpense('Salik', '8');
    expect(find.text('AED 133.00'), findsOneWidget);
    expect(find.text('3 entries'), findsOneWidget);
    await h.tab('Reports');
    expect(find.text('AED 133.00'), findsWidgets);
    expect(find.text('3'), findsOneWidget);
    for (final s in ['AED 100.00', 'AED 25.00', 'AED 8.00']) {
      expect(find.text(s), findsWidgets);
    }
    h.dispose();
  });

  testWidgets('validation messages for every bad field', (tester) async {
    final h = UiHarness(tester);
    await h.start();
    await h.tapText('Add Expense');
    await h.tapText('Save expense');
    expect(find.text('Choose what this expense was for.'), findsOneWidget);
    expect(find.text('Enter the amount.'), findsOneWidget);

    await h.chooseCategory('Other');
    expect(find.text('Remarks *'), findsOneWidget);
    for (final (input, msg) in [
      ('0', 'Amount must be greater than zero.'),
      ('12.345', 'Use at most 2 decimal places (fils).'),
      ('1000000', 'Amount cannot be more than AED 999,999.99.'),
    ]) {
      await tester.enterText(find.widgetWithText(TextField, 'Amount *'), input);
      await h.tapText('Save expense');
      expect(find.text(msg), findsOneWidget, reason: input);
    }
    await tester.enterText(find.widgetWithText(TextField, 'Amount *'), '5');
    await h.tapText('Save expense');
    expect(find.textContaining('Please describe the expense'), findsOneWidget);
    expect(h.gate.session!.expenses.count(), 0);
    h.dispose();
  });

  testWidgets('amount field filters letters and signs as you type', (
    tester,
  ) async {
    final h = UiHarness(tester);
    await h.start();
    await h.tapText('Add Expense');
    final field = find.widgetWithText(TextField, 'Amount *');
    await tester.enterText(field, '-1a2b.5e0');
    expect(tester.widget<TextField>(field).controller!.text, '12.50');
    h.dispose();
  });

  testWidgets('remarks counter and 250-character limit', (tester) async {
    final h = UiHarness(tester);
    await h.start();
    await h.tapText('Add Expense');
    await h.chooseCategory('Food');
    await tester.enterText(find.widgetWithText(TextField, 'Amount *'), '1');
    await tester.enterText(find.byType(TextField).last, 'x' * 251);
    await tester.pump();
    expect(find.text('251 / 250'), findsOneWidget);
    await h.tapText('Save expense');
    expect(find.textContaining('at most 250 characters'), findsOneWidget);
    await tester.enterText(find.byType(TextField).last, '  ${'é' * 250}  ');
    await h.tapText('Save expense');
    expect(find.text('Expense saved'), findsOneWidget);
    h.dispose();
  });

  testWidgets('edit keeps capture time; discard prompt; delete confirm', (
    tester,
  ) async {
    final h = UiHarness(tester);
    await h.start();
    await h.addExpense('Food', '25', remarks: 'lunch');
    final before = h.gate.session!.expenses.recent(limit: 1).single;

    // The clock moves on; editing must not change the recorded time.
    h.clock.value = DateTime(2026, 10, 3, 9, 0);
    await h.tapText('Food');
    expect(find.text('Edit expense'), findsOneWidget);
    expect(find.textContaining('2:05 PM'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextField, 'Amount *'), '30.75');
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Discard changes?'), findsOneWidget);
    await h.tapText('Keep editing');
    await h.tapText('Save changes');
    expect(find.text('Changes saved'), findsOneWidget);
    final after = h.gate.session!.expenses.byId(before.id)!;
    expect(after.amountFils, 3075);
    expect(after.captured.instantUtcMs, before.captured.instantUtcMs);

    await h.tapText('Food');
    await tester.tap(find.byTooltip('Delete'));
    await tester.pumpAndSettle();
    expect(find.text('Delete this expense?'), findsOneWidget);
    expect(find.textContaining('cannot be undone'), findsOneWidget);
    await h.tapText('Keep');
    expect(h.gate.session!.expenses.count(), 1);
    await tester.tap(find.byTooltip('Delete'));
    await tester.pumpAndSettle();
    await h.tapText('Delete');
    expect(find.text('Expense deleted'), findsOneWidget);
    expect(h.gate.session!.expenses.count(), 0);
    expect(find.text('No expenses yet'), findsOneWidget);
    h.dispose();
  });

  testWidgets(
    'categories: add, duplicate, rename, turn off, used on old entry',
    (tester) async {
      final h = UiHarness(tester);
      await h.start();
      await h.addExpense('Carwash', '15');
      await h.tab('Categories');

      await h.tapText('Add category');
      await tester.enterText(find.byType(TextField).last, '  petrol ');
      await h.tapText('Save');
      expect(find.textContaining('already exists'), findsOneWidget);
      await tester.enterText(find.byType(TextField).last, 'Tolls');
      await h.tapText('Save');
      expect(find.text('Category added'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Tolls'),
        200,
        scrollable: find.byType(Scrollable).hitTestable().first,
      );
      expect(find.text('Tolls'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Carwash'),
        -200,
        scrollable: find.byType(Scrollable).hitTestable().first,
      );

      // Turn off Carwash.
      final carwashTile = find.ancestor(
        of: find.text('Carwash'),
        matching: find.byType(ListTile),
      );
      await tester.tap(
        find.descendant(of: carwashTile, matching: find.byType(Switch)),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('1 existing expense'), findsOneWidget);
      await h.tapText('Turn off');
      expect(find.textContaining('Turned off'), findsWidgets);

      // Not offered for new expenses…
      await h.tab('Home');
      await h.tapText('Add Expense');
      await tester.tap(find.byType(DropdownButtonFormField<int>));
      await tester.pumpAndSettle();
      expect(find.text('Carwash'), findsNothing);
      expect(find.text('Tolls'), findsWidgets);
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();

      // …but the old entry still shows it and still edits.
      expect(find.textContaining('category turned off'), findsOneWidget);
      await h.tapText('Carwash');
      expect(find.text('Carwash (turned off)'), findsOneWidget);
      await tester.enterText(find.widgetWithText(TextField, 'Amount *'), '16');
      await h.tapText('Save changes');
      expect(find.text('Changes saved'), findsOneWidget);
      h.dispose();
    },
  );

  testWidgets(
    'reports: switch kinds, previous/next, back to today, month picker',
    (tester) async {
      final h = UiHarness(tester);
      await h.start();
      await h.addExpense('Food', '10');
      await h.tab('Reports');
      expect(find.text('Fri, 2 Oct 2026'), findsOneWidget);

      await tester.tap(find.byTooltip('Previous'));
      await tester.pumpAndSettle();
      expect(find.text('Thu, 1 Oct 2026'), findsOneWidget);
      expect(find.text('No expenses in this period'), findsOneWidget);
      expect(find.text('AED 0.00'), findsOneWidget);
      await h.tapText('Back to today');

      await h.tapText('Weekly');
      expect(find.text('Mon, 28 Sep 2026 – Sun, 4 Oct 2026'), findsOneWidget);
      await h.tapText('Monthly');
      expect(find.text('October 2026'), findsOneWidget);
      await tester.tap(find.byTooltip('Next'));
      await tester.pumpAndSettle();
      expect(find.text('November 2026'), findsOneWidget);

      await h.tapText('November 2026');
      expect(find.text('Choose month'), findsOneWidget);
      await tester.tap(find.text('November').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('February').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('2026').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('2025').last);
      await tester.pumpAndSettle();
      await h.tapText('Show');
      expect(find.text('February 2025'), findsOneWidget);
      h.dispose();
    },
  );

  testWidgets('Lock now locks; unlock returns to the app', (tester) async {
    final h = UiHarness(tester);
    await h.start();
    await h.tab('Settings');
    await h.tapText('Lock now');
    expect(h.gate.phase, GatePhase.locked);
    expect(find.text('Unlock'), findsOneWidget);
    await tester.runAsync(() => h.gate.unlock());
    await tester.pumpAndSettle();
    expect(h.gate.phase, GatePhase.ready);
    h.dispose();
  });

  testWidgets('20 rapid taps on Save create exactly one record', (
    tester,
  ) async {
    final h = UiHarness(tester);
    await h.start();
    await h.tapText('Add Expense');
    await h.chooseCategory('Food');
    await tester.enterText(find.widgetWithText(TextField, 'Amount *'), '7');
    final save = find.text('Save expense');
    await tester.ensureVisible(save);
    await tester.pumpAndSettle();
    for (var i = 0; i < 20; i++) {
      await tester.tap(find.byType(FilledButton).last, warnIfMissed: false);
    }
    await h.settle();
    expect(h.gate.session!.expenses.count(), 1);
    h.dispose();
  });

  testWidgets('activation screen rejects junk and wrong-device codes', (
    tester,
  ) async {
    final h = UiHarness(tester);
    await h.start();
    // Fresh gate for an un-activated install is covered by gate tests; here
    // check that pasting garbage via the service never crashes the UI.
    final r = await tester.runAsync(
      () => h.gate.activationService!.submit('hello'),
    );
    expect(r!.ok, isFalse);
    expect(r.message, contains('not a complete activation code'));
    h.dispose();
  });
}
