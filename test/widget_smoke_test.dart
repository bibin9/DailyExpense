import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:bcr_activation/bcr_activation.dart';
import 'package:daily_expense_tracker/config/app_config.dart';
import 'package:daily_expense_tracker/platform/storage_layout.dart';
import 'package:daily_expense_tracker/state/app_gate_controller.dart';
import 'package:daily_expense_tracker/ui/app_root.dart';
import 'package:daily_expense_tracker/ui/settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

/// Drives the real UI on a small phone screen (360×640) with fake platform
/// services: first launch → activation → add expense → reports → settings.
void main() {
  testWidgets('first launch to saved expense and report', (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final root = Directory.systemTemp.createTempSync('det_ui');
    final issuer = P256KeyPair.generate(Random(5));
    final platform = FakePlatform();
    final gate = AppGateController(
      config: AppConfig(
        clientId: 'insideout-casa',
        clientName: 'InsideOut Casa',
        issuerPublicKeyBase64: base64.encode(issuer.spki),
      ),
      platform: platform,
      keyStore: MemoryKeyStore(),
      auth: FakeAuth(),
      clock: FixedClock(DateTime(2026, 10, 2, 14, 5)),
      resolveLayout: () async =>
          StorageLayout(Directory('${root.path}/det_data')),
    );

    await tester.runAsync(() async {
      await tester.pumpWidget(DailyExpenseApp(gate: gate));
      for (var i = 0; i < 50 && gate.phase != GatePhase.needsActivation; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
    });
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Activate this phone for InsideOut Casa'),
      findsOneWidget,
    );
    expect(find.text('Copy request code'), findsOneWidget);

    // Administrator signs the request shown on screen.
    final req = ActivationRequest.parse(gate.activation!.requestCode!);
    final token = signActivationToken(
      ActivationClaims(
        clientId: req.clientId,
        fingerprint: req.fingerprint,
        issuedAt: DateTime.utc(2026, 10, 2),
      ),
      issuer,
    );
    await tester.enterText(find.byType(TextField), token);
    await tester.ensureVisible(find.text('Activate'));
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester.tap(find.text('Activate'));
      for (var i = 0; i < 50 && gate.phase != GatePhase.ready; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
    });
    await tester.pumpAndSettle();

    // Home: zero today, empty state, prominent Add Expense.
    expect(find.text('AED 0.00'), findsOneWidget);
    expect(find.text('No expenses yet'), findsOneWidget);
    await tester.tap(find.text('Add Expense'));
    await tester.pumpAndSettle();

    // Save with nothing chosen → validation, nothing saved.
    await tester.ensureVisible(find.text('Save expense'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save expense'));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump();
    expect(find.text('Choose what this expense was for.'), findsOneWidget);

    await tester.tap(find.byType(DropdownButtonFormField<int>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Petrol').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Amount *'), '100');
    await tester.ensureVisible(find.text('Save expense'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save expense'));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Expense saved'), findsOneWidget);
    expect(gate.session!.expenses.count(), 1);

    // Back to Home: total updated immediately.
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('AED 100.00'), findsWidgets);

    // Reports tab.
    await tester.tap(find.text('Reports'));
    await tester.pumpAndSettle();
    expect(find.text('By category'), findsOneWidget);
    expect(find.text('AED 100.00'), findsWidgets);

    // Settings tab shows the data-loss warning and BCR signature.
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('your records are kept only on this phone'),
      findsOneWidget,
    );
    await tester.scrollUntilVisible(
      find.textContaining('Crafted by BCR'),
      300,
      scrollable: find
          .descendant(
            of: find.byType(SettingsScreen),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(find.textContaining('Crafted by BCR'), findsOneWidget);

    gate.dispose();
    root.deleteSync(recursive: true);
  });
}
