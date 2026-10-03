import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'ui_harness.dart';

/// QA: pre-activated company build as staff experience it.
void main() {
  testWidgets('install → unlock → straight to Home, no codes', (tester) async {
    final h = UiHarness(tester);
    await h.start(companyLicence: true);
    expect(find.textContaining('Activate this phone'), findsNothing);
    expect(find.text('Copy request code'), findsNothing);
    expect(find.text('AED 0.00'), findsOneWidget);
    await h.addExpense('Food', '25');
    expect(find.text('AED 25.00'), findsWidgets);
    await h.tab('Settings');
    await tester.scrollUntilVisible(
      find.text('Company licence — active'),
      200,
      scrollable: find.byType(Scrollable).hitTestable().first,
    );
    expect(find.text('No end date'), findsOneWidget);
    h.dispose();
  });

  testWidgets(
    'licence ended: records visible, adding disabled, backup offered',
    (tester) async {
      final h = UiHarness(tester);
      await h.start(
        companyLicence: true,
        licenceExpires: DateTime.utc(
          2026,
          1,
          1,
        ), // already past (clock is Oct 2026)
      );
      expect(
        find.textContaining('licence for this app has ended'),
        findsOneWidget,
      );
      expect(find.text('Add Expense'), findsNothing);
      await h.tab('Categories');
      expect(find.text('Add category'), findsNothing);
      await h.tab('Settings');
      expect(find.text('Create backup'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Licence ended — read-only'),
        200,
        scrollable: find.byType(Scrollable).hitTestable().first,
      );
      h.dispose();
    },
  );
}
