import 'package:daily_expense_tracker/core/capture.dart';
import 'package:daily_expense_tracker/domain/models.dart';
import 'package:daily_expense_tracker/ui/expense_form_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'ui_harness.dart';

/// QA: small phone (320×568 logical px) with large accessibility font
/// sizes, long names and maximum values. Any layout overflow or exception
/// fails the test.
void main() {
  for (final scale in [1.0, 1.5, 2.0]) {
    testWidgets('all screens at 320×568, text scale $scale', (tester) async {
      final h = UiHarness(tester);
      await h.start(size: const Size(320, 568), textScale: scale);
      final s = h.gate.session!;

      final longCat = s.categories.add(
        'Vehicle Maintenance Workshop Al Quoz 12',
        nowUtcMs: 1,
      );
      for (var i = 0; i < 30; i++) {
        s.expenses.insert(
          ExpenseDraft(
            categoryId: i.isEven ? longCat.id : s.categories.active().first.id,
            amountFils: 99999999,
            remarks: 'Remark ${'with many words ' * 20}'.substring(0, 250),
          ),
          CaptureStamp.fromLocal(DateTime(2026, 10, 2, 8, i)),
          nowUtcMs: 1,
        );
      }
      s.dataChanged();
      await tester.pumpAndSettle();
      expect(find.text('AED 29,999,999.70'), findsOneWidget);
      // The primary action must stay reachable at any font size.
      expect(find.text('Add Expense').hitTestable(), findsOneWidget);

      final nav = tester.state<NavigatorState>(find.byType(Navigator).first);

      // Add form with worst-case input.
      nav.push(
        MaterialPageRoute<void>(builder: (_) => ExpenseFormScreen(session: s)),
      );
      await tester.pumpAndSettle();
      await h.chooseCategory('Vehicle Maintenance Workshop Al Quoz 12');
      await tester.enterText(
        find.widgetWithText(TextField, 'Amount *'),
        '999999.99',
      );
      await tester.enterText(find.byType(TextField).last, 'x' * 250);
      await tester.pumpAndSettle();
      final formList = find
          .descendant(
            of: find.descendant(
              of: find.byType(ExpenseFormScreen),
              matching: find.byType(ListView),
            ),
            matching: find.byType(Scrollable),
          )
          .first;
      final pos = tester.state<ScrollableState>(formList).position;
      pos.jumpTo(pos.maxScrollExtent);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Save expense'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save expense'));
      await h.settle();
      expect(s.expenses.count(), 31);
      nav.pop();
      await tester.pumpAndSettle();

      // Edit form for an entry with a long, later-deactivated category.
      final existing = s.expenses.recent(limit: 1).single;
      s.categories.setActive(longCat.id, false, nowUtcMs: 2);
      nav.push(
        MaterialPageRoute<void>(
          builder: (_) => ExpenseFormScreen(
            session: s,
            existing: s.expenses.byId(existing.id),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Edit expense'), findsOneWidget);
      await tester.fling(
        find.byType(Scrollable).hitTestable().first,
        const Offset(0, -2000),
        3000,
      );
      await tester.pumpAndSettle();
      nav.pop();
      await tester.pumpAndSettle();

      for (final tab in ['Reports', 'Categories', 'Settings', 'Home']) {
        await h.tab(tab);
        await tester.fling(
          find.byType(Scrollable).hitTestable().first,
          const Offset(0, -4000),
          3000,
        );
        await tester.pumpAndSettle();
      }
      await h.tab('Reports');
      for (final kind in ['Weekly', 'Monthly']) {
        await tester.fling(
          find.byType(Scrollable).hitTestable().first,
          const Offset(0, 8000),
          3000,
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text(kind));
        await tester.pumpAndSettle();
        await tester.fling(
          find.byType(Scrollable).hitTestable().first,
          const Offset(0, -6000),
          3000,
        );
        await tester.pumpAndSettle();
      }

      h.gate.lockNow();
      await tester.pumpAndSettle();
      expect(find.text('Unlock'), findsOneWidget);
      h.dispose();
    });
  }
}
