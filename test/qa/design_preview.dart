@Tags(['preview'])
library;

import 'package:daily_expense_tracker/core/capture.dart';
import 'package:daily_expense_tracker/domain/models.dart';
import 'package:daily_expense_tracker/ui/expense_form_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'ui_harness.dart';

/// Renders the main screens to PNGs for design review:
///   flutter test test/qa/design_preview.dart --update-goldens
/// Output: test/qa/previews/*.png (not a pass/fail check).
void main() {
  testWidgets('design previews', (tester) async {
    final h = UiHarness(tester);
    await h.start(size: const Size(390, 844), companyLicence: true);
    final s = h.gate.session!;
    final cats = {for (final c in s.categories.active()) c.name: c.id};
    void add(String cat, int fils, int hour, int min, [String? r]) =>
        s.expenses.insert(
          ExpenseDraft(categoryId: cats[cat]!, amountFils: fils, remarks: r),
          CaptureStamp.fromLocal(DateTime(2026, 10, 2, hour, min)),
          nowUtcMs: 1,
        );
    add('Petrol', 10000, 8, 10, 'Vehicle D 45120');
    add('Salik', 800, 9, 2);
    add('Food', 2500, 13, 30, 'Lunch at site');
    add('Car Parking Fee', 1000, 15, 45, 'JLT tower');
    add('Labor', 15000, 17, 5, 'Helper – villa 14');
    s.expenses.insert(
      ExpenseDraft(
        categoryId: cats['Carwash']!,
        amountFils: 3500,
        remarks: null,
      ),
      CaptureStamp.fromLocal(DateTime(2026, 10, 1, 18, 20)),
      nowUtcMs: 1,
    );
    s.meta.write('last_backup_at', '${s.nowUtcMs()}');
    s.dataChanged();
    await tester.pumpAndSettle();

    Future<void> shot(String name) => expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('previews/$name.png'),
    );

    await shot('1_home');
    final nav = tester.state<NavigatorState>(find.byType(Navigator).first);
    nav.push(
      MaterialPageRoute<void>(builder: (_) => ExpenseFormScreen(session: s)),
    );
    await tester.pumpAndSettle();
    await h.chooseCategory('Food');
    await tester.enterText(find.widgetWithText(TextField, 'Amount *'), '25.50');
    await tester.pumpAndSettle();
    await shot('2_add_expense');
    nav.pop();
    await tester.pumpAndSettle();
    await h.tab('Reports');
    await shot('3_reports');
    await h.tab('Categories');
    await shot('4_categories');
    await h.tab('Settings');
    await shot('5_settings');
    h.gate.lockNow();
    await tester.pumpAndSettle();
    await shot('6_lock');
    h.dispose();
  });
}
