import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:bcr_activation/bcr_activation.dart';
import 'package:daily_expense_tracker/config/app_config.dart';
import 'package:daily_expense_tracker/data/failures.dart';
import 'package:daily_expense_tracker/domain/models.dart';
import 'package:daily_expense_tracker/platform/storage_layout.dart';
import 'package:daily_expense_tracker/security/device_auth.dart';
import 'package:daily_expense_tracker/state/app_gate_controller.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';
import 'helpers.dart';

void main() {
  late Directory root;
  late FakePlatform platform;
  late MemoryKeyStore keys;
  late FakeAuth auth;
  late FixedClock clock;
  final issuer = P256KeyPair.generate(Random(11));
  final config = AppConfig(
    clientId: 'insideout-casa',
    clientName: 'InsideOut Casa',
    issuerPublicKeyBase64: base64.encode(issuer.spki),
  );

  AppGateController gate() => AppGateController(
    config: config,
    platform: platform,
    keyStore: keys,
    auth: auth,
    clock: clock,
    resolveLayout: () async =>
        StorageLayout(Directory('${root.path}/det_data')),
  );

  setUp(() {
    root = Directory.systemTemp.createTempSync('det_gate');
    platform = FakePlatform();
    keys = MemoryKeyStore();
    auth = FakeAuth();
    clock = FixedClock(DateTime(2026, 10, 2, 9));
  });
  tearDown(() => root.deleteSync(recursive: true));

  Future<AppGateController> activated() async {
    final g = gate();
    await g.start();
    final req = ActivationRequest.parse(g.activation!.requestCode!);
    final token = signActivationToken(
      ActivationClaims(
        clientId: req.clientId,
        fingerprint: req.fingerprint,
        issuedAt: DateTime.utc(2026),
      ),
      issuer,
    );
    expect((await g.submitActivation(token)).ok, isTrue);
    return g;
  }

  test(
    'first launch: unlock → empty encrypted db → activation → ready',
    () async {
      final g = gate();
      await g.start();
      expect(auth.calls, 1);
      expect(g.phase, GatePhase.needsActivation);
      expect(keys.value, hasLength(32));
      expect(File('${root.path}/det_data/expenses.db').existsSync(), isTrue);
      expect(platform.excluded.any((p) => p.endsWith('det_data')), isTrue);
      expect(platform.excluded.any((p) => p.endsWith('expenses.db')), isTrue);
      g.dispose();
      final g2 = await activated();
      expect(g2.phase, GatePhase.ready);
      g2.dispose();
    },
  );

  test(
    'restart keeps data and activation (persistence across restarts)',
    () async {
      final g = await activated();
      final s = g.session!;
      s.expenses.insert(
        ExpenseDraft(
          categoryId: s.categories.active().first.id,
          amountFils: 4200,
          remarks: null,
        ),
        dubai(2026, 10, 2),
        nowUtcMs: 1,
      );
      g.dispose();

      final again = gate();
      await again.start();
      expect(again.phase, GatePhase.ready);
      expect(again.session!.expenses.count(), 1);
      expect(platform.deleteCalls, 1); // only the first-ever launch cleaned up
      again.dispose();
    },
  );

  test(
    'reinstall (iOS keychain survived, app files gone) starts clean',
    () async {
      final g = await activated();
      g.dispose();
      final oldKey = keys.value;
      // Uninstall removes the app's files but not Keychain items.
      Directory('${root.path}/det_data').deleteSync(recursive: true);

      final fresh = gate();
      await fresh.start();
      expect(fresh.phase, GatePhase.needsActivation);
      expect(keys.value, isNot(equals(oldKey)));
      fresh.dispose();
    },
  );

  test(
    'upgrade without marker but with existing db keeps data and key',
    () async {
      final g = await activated();
      g.dispose();
      final key = keys.value;
      File('${root.path}/det_data/install.marker').deleteSync();
      final up = gate();
      await up.start();
      expect(up.phase, GatePhase.ready);
      expect(keys.value, key);
      up.dispose();
    },
  );

  test(
    'missing key with existing database is a safe error, not a wipe',
    () async {
      final g = await activated();
      g.dispose();
      keys.value = null;
      final g2 = gate();
      await g2.start();
      expect(g2.phase, GatePhase.startupError);
      expect(g2.failure!.kind, FailureKind.keyUnavailable);
      expect(File('${root.path}/det_data/expenses.db').existsSync(), isTrue);
      g2.dispose();
    },
  );

  test('no device screen lock blocks the app with instructions', () async {
    auth.secure = false;
    final g = gate();
    await g.start();
    expect(g.phase, GatePhase.noDeviceSecurity);
    expect(g.session, isNull);
    g.dispose();
  });

  test('cancel and lockout keep the app locked with a message', () async {
    auth.next = AuthOutcome.cancelled;
    final g = gate();
    await g.start();
    expect(g.phase, GatePhase.locked);
    expect(g.session, isNull);
    auth.next = AuthOutcome.lockedOut;
    await g.unlock();
    expect(g.message, contains('Too many attempts'));
    auth.next = AuthOutcome.success;
    await g.unlock();
    expect(g.phase, GatePhase.needsActivation);
    g.dispose();
  });

  test('relocks after 2 minutes in background, not after 1 minute', () async {
    final g = await activated();
    g.didChangeAppLifecycleState(AppLifecycleState.paused);
    expect(g.obscured, isTrue);
    clock.value = clock.value.add(const Duration(seconds: 60));
    g.didChangeAppLifecycleState(AppLifecycleState.resumed);
    expect(g.phase, GatePhase.ready);
    expect(g.obscured, isFalse);

    auth.next = AuthOutcome.cancelled;
    g.didChangeAppLifecycleState(AppLifecycleState.paused);
    clock.value = clock.value.add(const Duration(minutes: 2));
    g.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await pumpEventQueue();
    expect(g.phase, GatePhase.locked);
    g.dispose();
  });
}
