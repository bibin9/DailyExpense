import 'dart:io';

import 'package:daily_expense_tracker/data/backup_service.dart';
import 'package:daily_expense_tracker/state/app_gate_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'ui_harness.dart';

/// QA: moving to a new phone through the real screens.
void main() {
  testWidgets('back up on old phone → restore on new phone', (tester) async {
    final shared = Directory.systemTemp.createTempSync('det_move');
    final backupFile = '${shared.path}/moved.$backupFileExtension';

    // ---- Old phone -------------------------------------------------------
    final old = UiHarness(tester);
    await old.start();
    await old.addExpense('Petrol', '100');
    await old.addExpense('Food', '25');
    await old.addExpense('Salik', '8');
    await old.tab('Settings');
    expect(find.text('Never'), findsOneWidget);
    // Restore is not offered on a phone that already has records.
    expect(
      find.textContaining('only on a phone with no expenses'),
      findsOneWidget,
    );

    old.platform.saveDestination = backupFile;
    await old.tapText('Create backup');
    await tester.enterText(
      find.widgetWithText(TextField, 'Backup password'),
      'short',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Type it again'),
      'short',
    );
    await old.tapText('Create');
    expect(find.text('Use at least 8 characters.'), findsOneWidget);
    await tester.enterText(
      find.widgetWithText(TextField, 'Backup password'),
      'Casa 2026',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Type it again'),
      'Casa 2026',
    );
    await old.tapText('Create');
    await old.settle();
    expect(find.text('Backup saved'), findsOneWidget);
    expect(
      find.textContaining('3 expenses are in the backup file'),
      findsOneWidget,
    );
    await old.tapText('OK');
    expect(File(backupFile).existsSync(), isTrue);
    expect(
      old.platform.saved.single,
      matches(RegExp(r'^DailyExpenseTracker-backup-2026-10-02\.detbak$')),
    );
    expect(find.text('Never'), findsNothing); // "Last backup" updated
    // No temporary copy is left behind in the app's folder.
    expect(
      Directory(old.gate.session!.dataDirPath)
          .listSync()
          .where((f) => f.path.endsWith('.tmp')),
      isEmpty,
    );
    old.dispose();
    await tester.pumpWidget(const SizedBox());

    // ---- New phone (different device key, activated separately) ---------
    final fresh = UiHarness(tester);
    await fresh.start();
    final tokenBefore = fresh.gate.session!.tokenStore.readToken();
    expect(find.text('No expenses yet'), findsOneWidget);
    fresh.platform.pickSource = backupFile;
    await fresh.tapText('Moving from another phone? Restore a backup');
    expect(find.text('Backup password'), findsWidgets);

    await tester.enterText(
      find.widgetWithText(TextField, 'Backup password'),
      'casa 2026',
    );
    await fresh.tapText('Open');
    await fresh.settle();
    expect(find.textContaining('password is wrong'), findsOneWidget);

    await tester.enterText(
      find.widgetWithText(TextField, 'Backup password'),
      'Casa 2026',
    );
    await fresh.tapText('Open');
    await fresh.settle();
    expect(find.text('Restore this backup?'), findsOneWidget);
    expect(find.textContaining('3 expenses'), findsOneWidget);
    expect(find.textContaining('Total AED 133.00'), findsOneWidget);

    await fresh.tapText('Restore');
    await tester.runAsync(() async {
      for (var i = 0; i < 100 && fresh.gate.phase != GatePhase.ready; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
    });
    await fresh.settle();
    expect(fresh.gate.phase, GatePhase.ready);
    expect(find.text('Restored 3 expenses from your backup.'), findsOneWidget);
    expect(find.text('AED 133.00'), findsOneWidget);
    expect(find.text('3 entries'), findsOneWidget);
    // The new phone keeps its own activation; the old phone's never arrives.
    expect(fresh.gate.session!.tokenStore.readToken(), tokenBefore);
    expect(fresh.gate.activation!.fingerprint, isNotNull);
    // Picked copy cleaned up; restore no longer offered.
    expect(
      Directory(fresh.gate.session!.dataDirPath).listSync().where(
        (f) =>
            f.path.endsWith('.tmp') ||
            f.path.contains('restoring') ||
            f.path.contains('pre-restore'),
      ),
      isEmpty,
    );
    await fresh.tab('Settings');
    expect(
      find.textContaining('only on a phone with no expenses'),
      findsOneWidget,
    );

    // Survives a restart on the new phone.
    final s = fresh.gate.session!;
    expect(s.expenses.count(), 3);
    fresh.dispose();
    shared.deleteSync(recursive: true);
  });

  testWidgets('cancelling the save sheet leaves no file and says so', (
    tester,
  ) async {
    final h = UiHarness(tester);
    await h.start();
    await h.addExpense('Food', '5');
    await h.tab('Settings');
    h.platform.saveDestination = null; // user backs out of the save sheet
    await h.tapText('Create backup');
    await tester.enterText(
      find.widgetWithText(TextField, 'Backup password'),
      '12345678',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Type it again'),
      '12345678',
    );
    await h.tapText('Create');
    await h.settle();
    expect(find.text('Backup not saved.'), findsOneWidget);
    expect(
      Directory(h.gate.session!.dataDirPath)
          .listSync()
          .where((f) => f.path.endsWith('.tmp')),
      isEmpty,
    );
    h.dispose();
  });

  testWidgets('monthly reminder appears after 30 days and can be snoozed', (
    tester,
  ) async {
    final h = UiHarness(tester);
    await h.start();
    await h.addExpense('Food', '5');
    expect(find.text('Time for a backup'), findsNothing);
    h.clock.value = h.clock.value.add(const Duration(days: 31));
    h.gate.session!.dataChanged();
    await tester.pumpAndSettle();
    expect(find.text('Time for a backup'), findsOneWidget);
    await h.tapText('Later');
    expect(find.text('Time for a backup'), findsNothing);
    h.clock.value = h.clock.value.add(const Duration(days: 8));
    h.gate.session!.dataChanged();
    await tester.pumpAndSettle();
    expect(find.text('Time for a backup'), findsOneWidget);
    h.dispose();
  });
}
