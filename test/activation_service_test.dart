import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:bcr_activation/bcr_activation.dart';
import 'package:daily_expense_tracker/config/app_config.dart';
import 'package:daily_expense_tracker/security/activation_service.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

class MemTokens implements TokenStore {
  String? v;
  @override
  void deleteToken() => v = null;
  @override
  String? readToken() => v;
  @override
  void writeToken(String token) => v = token;
}

void main() {
  final issuer = P256KeyPair.generate(Random(7));
  final config = AppConfig(
    clientId: 'insideout-casa',
    clientName: 'InsideOut Casa',
    issuerPublicKeyBase64: base64.encode(issuer.spki),
  );
  final now = DateTime.utc(2026, 10, 2);

  ActivationService service(
    FakePlatform p,
    MemTokens t, {
    bool bypass = false,
  }) => ActivationService(
    config: config,
    platform: p,
    tokens: t,
    now: () => now,
    devBypassActive: bypass,
    random: Random(3),
  );

  /// What the administrator does with det_admin.
  String adminSigns(String requestCode, {P256KeyPair? signer}) {
    final req = ActivationRequest.parse(requestCode);
    return signActivationToken(
      ActivationClaims(
        clientId: req.clientId,
        fingerprint: req.fingerprint,
        issuedAt: now,
      ),
      signer ?? issuer,
    );
  }

  test(
    'valid device: request → admin token → activated, and stays activated',
    () async {
      final phone = FakePlatform(seed: 1);
      final tokens = MemTokens();
      final s = service(phone, tokens);
      final first = await s.check();
      expect(first.phase, ActivationPhase.needsActivation);
      expect(first.requestCode, startsWith('DETREQ1:insideout-casa:'));

      final r = await s.submit(adminSigns(first.requestCode!));
      expect(r.ok, isTrue, reason: r.message);
      expect((await s.check()).phase, ActivationPhase.activated);
    },
  );

  test('different device: token for phone A is rejected on phone B', () async {
    final a = FakePlatform(seed: 1);
    final tokenA = adminSigns(
      (await service(a, MemTokens()).check()).requestCode!,
    );

    final b = FakePlatform(seed: 2);
    final r = await service(b, MemTokens()).submit(tokenA);
    expect(r.ok, isFalse);
    expect(r.message, contains('different phone'));
  });

  test(
    'copying data + token to another phone fails at start-up check',
    () async {
      final a = FakePlatform(seed: 1);
      final tokens = MemTokens();
      final sa = service(a, tokens);
      await sa.submit(adminSigns((await sa.check()).requestCode!));

      final b = FakePlatform(seed: 2)..key = null; // other phone, no key yet
      final state = await service(b, tokens).check();
      expect(state.phase, ActivationPhase.needsActivation);
      expect(tokens.v, isNull); // stale token dropped
    },
  );

  test('key present but private key not usable → not activated', () async {
    final a = FakePlatform(seed: 1);
    final tokens = MemTokens();
    final s = service(a, tokens);
    await s.submit(adminSigns((await s.check()).requestCode!));
    // Public key reports the bound key, but signing uses another key.
    final spoof = _SpoofPlatform(a);
    expect(
      (await service(spoof, tokens).check()).phase,
      ActivationPhase.needsActivation,
    );
  });

  test('modified token and wrong issuer are rejected', () async {
    final a = FakePlatform(seed: 1);
    final s = service(a, MemTokens());
    final code = (await s.check()).requestCode!;
    final good = adminSigns(code);
    final parts = good.split('.');
    final tampered = '${parts[0]}.${parts[1]}x.${parts[2]}';
    expect((await s.submit(tampered)).ok, isFalse);
    expect(
      (await s.submit(
        adminSigns(code, signer: P256KeyPair.generate(Random(99))),
      )).ok,
      isFalse,
    );
    expect((await s.submit('not a token')).ok, isFalse);
  });

  group('development bypass', () {
    test('policy: never allowed outside debug builds', () {
      expect(devBypassAllowed(isDebugBuild: false, requested: true), isFalse);
      expect(devBypassAllowed(isDebugBuild: false, requested: false), isFalse);
      expect(devBypassAllowed(isDebugBuild: true, requested: false), isFalse);
      expect(devBypassAllowed(isDebugBuild: true, requested: true), isTrue);
    });

    test('tests are built without DET_DEV_BYPASS, so the constant is off', () {
      expect(AppConfig.devBypassActive, isFalse);
    });

    test('a service built with release defaults requires activation', () async {
      final s = ActivationService(
        config: config,
        platform: FakePlatform(),
        tokens: MemTokens(),
        now: () => now,
      );
      expect((await s.check()).phase, ActivationPhase.needsActivation);
    });
  });

  test('unconfigured build cannot be activated', () async {
    final s = ActivationService(
      config: const AppConfig(
        clientId: '',
        clientName: '',
        issuerPublicKeyBase64: '',
      ),
      platform: FakePlatform(),
      tokens: MemTokens(),
      now: () => now,
    );
    expect((await s.check()).phase, ActivationPhase.notConfigured);
  });
}

class _SpoofPlatform extends FakePlatform {
  _SpoofPlatform(this.real) : super(seed: 50);
  final FakePlatform real;
  @override
  Future<Uint8List?> installationPublicKey() => real.installationPublicKey();
  @override
  Future<Uint8List> signWithInstallationKey(Uint8List data) async =>
      P256KeyPair.generate(Random(51)).signDer(data);
}
