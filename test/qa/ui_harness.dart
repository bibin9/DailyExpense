import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:bcr_activation/bcr_activation.dart';
import 'package:daily_expense_tracker/config/app_config.dart';
import 'package:daily_expense_tracker/platform/storage_layout.dart';
import 'package:daily_expense_tracker/state/app_gate_controller.dart';
import 'package:daily_expense_tracker/ui/app_root.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fakes.dart';

/// Boots the real app UI with fake platform services and activates it.
class UiHarness {
  UiHarness(this.tester);
  final WidgetTester tester;
  late final Directory root;
  late final AppGateController gate;
  late final FakeAuth auth;
  late final FixedClock clock;
  late final FakePlatform platform;

  static bool _fontLoaded = false;
  static int _seed = 1;

  /// Tests normally render with a block font whose glyphs are ~2x wider
  /// than real text. Load a real font under the theme's family name so
  /// layout and wrapping match a phone.
  static Future<void> loadRealFont() async {
    if (_fontLoaded) return;
    const candidates = [
      'C:/Windows/Fonts/arial.ttf',
      '/System/Library/Fonts/Supplemental/Arial.ttf',
      '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf',
    ];
    for (final path in candidates) {
      final f = File(path);
      if (f.existsSync()) {
        final bytes = f.readAsBytesSync();
        final loader = FontLoader('Roboto')
          ..addFont(Future.value(ByteData.sublistView(bytes)));
        await loader.load();
        _fontLoaded = true;
        return;
      }
    }
  }

  Future<void> start({
    Size size = const Size(360, 640),
    double textScale = 1,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    await tester.runAsync(loadRealFont);
    root = Directory.systemTemp.createTempSync('det_qa_ui');
    final issuer = P256KeyPair.generate(Random(5));
    auth = FakeAuth();
    clock = FixedClock(DateTime(2026, 10, 2, 14, 5));
    gate = AppGateController(
      config: AppConfig(
        clientId: 'insideout-casa',
        clientName: 'InsideOut Casa',
        issuerPublicKeyBase64: base64.encode(issuer.spki),
      ),
      platform: platform = FakePlatform(seed: _seed++),
      keyStore: MemoryKeyStore(),
      auth: auth,
      clock: clock,
      resolveLayout: () async =>
          StorageLayout(Directory('${root.path}/det_data')),
    );
    await tester.runAsync(() async {
      await tester.pumpWidget(DailyExpenseApp(gate: gate));
      await _until(() => gate.phase == GatePhase.needsActivation);
    });
    await tester.pumpAndSettle();
    final req = ActivationRequest.parse(gate.activation!.requestCode!);
    final token = signActivationToken(
      ActivationClaims(
        clientId: req.clientId,
        fingerprint: req.fingerprint,
        issuedAt: DateTime.utc(2026, 10, 2),
      ),
      issuer,
    );
    await tester.runAsync(() async {
      await gate.submitActivation(token);
    });
    await tester.pumpAndSettle();
    expect(gate.phase, GatePhase.ready);
  }

  Future<void> _until(bool Function() cond) async {
    for (var i = 0; i < 100 && !cond(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
  }

  /// Lets real async work (platform futures, DB) complete, then settles.
  Future<void> settle() async {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 60)),
    );
    await tester.pumpAndSettle();
  }

  Future<void> tapText(String text) async {
    if (find.text(text).evaluate().isEmpty) {
      await tester.scrollUntilVisible(
        find.text(text),
        250,
        scrollable: find.byType(Scrollable).hitTestable().first,
      );
    }
    final f = find.text(text).last;
    await tester.ensureVisible(f);
    await tester.pumpAndSettle();
    await tester.tap(f);
    await settle();
  }

  Future<void> addExpense(
    String category,
    String amount, {
    String? remarks,
  }) async {
    await tapText('Add Expense');
    await chooseCategory(category);
    await tester.enterText(find.widgetWithText(TextField, 'Amount *'), amount);
    if (remarks != null) {
      await tester.enterText(find.byType(TextField).last, remarks);
    }
    await tapText('Save expense');
    expect(find.text('Expense saved'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
  }

  Future<void> chooseCategory(String name) async {
    final dropdown = find.byType(DropdownButtonFormField<int>);
    if (dropdown.evaluate().isEmpty) {
      await tester.scrollUntilVisible(
        dropdown,
        150,
        scrollable: find.byType(Scrollable).hitTestable().first,
      );
    }
    await tester.ensureVisible(dropdown);
    await tester.pumpAndSettle();
    await tester.tap(dropdown);
    await tester.pumpAndSettle();
    await tester.tap(find.text(name).last);
    await tester.pumpAndSettle();
  }

  Future<void> tab(String label) async {
    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text(label),
      ),
    );
    await tester.pumpAndSettle();
  }

  void dispose() {
    gate.dispose();
    root.deleteSync(recursive: true);
  }
}
