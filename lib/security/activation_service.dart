import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:bcr_activation/bcr_activation.dart';

import '../config/app_config.dart';
import '../platform/platform_services.dart';

enum ActivationPhase {
  /// Build has no valid client id / issuer key (release check prevents this).
  notConfigured,
  needsActivation,
  activated,

  /// Debug-only bypass. Unreachable in release builds.
  devBypass,
}

class ActivationState {
  const ActivationState(
    this.phase, {
    this.requestCode,
    this.fingerprint,
    this.claims,
    this.problem,
  });

  final ActivationPhase phase;
  final String? requestCode;
  final String? fingerprint;
  final ActivationClaims? claims;

  /// Why a previously stored token is no longer accepted (shown to user).
  final String? problem;
}

/// Where the activation token is kept (inside the encrypted database).
abstract interface class TokenStore {
  String? readToken();
  void writeToken(String token);
  void deleteToken();
}

String describeActivationStatus(ActivationStatus s) => switch (s) {
  ActivationStatus.valid => 'Activated.',
  ActivationStatus.malformed => 'That is not a complete activation code. Copy the whole code and try again.',
  ActivationStatus.unsupportedAlgorithm || ActivationStatus.badSignature =>
    'This activation code is not valid. It may have been changed or '
        'issued by someone else.',
  ActivationStatus.wrongClient =>
    'This activation code was issued for a different company.',
  ActivationStatus.wrongDevice =>
    'This activation code belongs to a different phone or installation. '
        'Send the request code shown on this screen to your administrator.',
  ActivationStatus.expired =>
    'This activation has expired. Ask your administrator for a new code.',
};

/// Offline installation activation.
///
/// 1. The phone creates a P-256 key pair inside the keystore (private key is
///    not exportable) and shows a request code with the public-key
///    fingerprint.
/// 2. The administrator signs it with the issuer key (admin_cli).
/// 3. The app verifies the token with the embedded issuer PUBLIC key and
///    that it is bound to this installation's fingerprint.
/// 4. On every start it also proves the bound private key is present by
///    signing a fresh random challenge and verifying it — so copying the app
///    data and token to another phone does not work.
class ActivationService {
  ActivationService({
    required this.config,
    required this.platform,
    required this.tokens,
    required this.now,
    this.devBypassActive = AppConfig.devBypassActive,
    Random? random,
  }) : _random = random ?? Random.secure();

  final AppConfig config;
  final PlatformServices platform;
  final TokenStore tokens;
  final DateTime Function() now;
  final bool devBypassActive;
  final Random _random;

  Future<String> _fingerprint() async =>
      installationFingerprint(await platform.ensureInstallationKey());

  Future<ActivationState> _needs(String? problem) async {
    final fp = await _fingerprint();
    return ActivationState(
      ActivationPhase.needsActivation,
      fingerprint: fp,
      requestCode: ActivationRequest(
        clientId: config.clientId,
        fingerprint: fp,
      ).encode(),
      problem: problem,
    );
  }

  /// Proof of possession: the private key behind [publicKey] is in this
  /// device's keystore right now.
  Future<bool> _proveKeyPresent(Uint8List publicKey) async {
    final challenge = Uint8List.fromList([
      ...utf8.encode('det-proof-v1:'),
      ...List.generate(32, (_) => _random.nextInt(256)),
    ]);
    try {
      final sig = await platform.signWithInstallationKey(challenge);
      return verifyP256Der(publicKey, challenge, sig);
    } on Object {
      return false;
    }
  }

  Future<ActivationState> check() async {
    if (devBypassActive) {
      return const ActivationState(ActivationPhase.devBypass);
    }
    final issuer = config.issuerPublicKey;
    if (!config.isComplete || issuer == null) {
      return const ActivationState(ActivationPhase.notConfigured);
    }
    final token = tokens.readToken();
    if (token == null) return _needs(null);

    final existingKey = await platform.installationPublicKey();
    if (existingKey == null) {
      // Token present but key gone: data was moved/restored to another
      // device or the keystore was reset.
      tokens.deleteToken();
      return _needs(
        'This phone needs to be activated again (its security key changed).',
      );
    }
    final fp = installationFingerprint(existingKey);
    final result = verifyActivationToken(
      token: token,
      issuerPublicKey: issuer,
      expectedClientId: config.clientId,
      deviceFingerprint: fp,
      now: now(),
    );
    if (!result.isValid) {
      return _needs(describeActivationStatus(result.status));
    }
    if (!await _proveKeyPresent(existingKey)) {
      return _needs(
        'This phone\'s security key could not be verified. '
        'Please activate again.',
      );
    }
    return ActivationState(
      ActivationPhase.activated,
      fingerprint: fp,
      claims: result.claims,
    );
  }

  /// Verifies and stores a token typed/pasted by the user.
  Future<({bool ok, String message})> submit(String rawToken) async {
    final issuer = config.issuerPublicKey;
    if (issuer == null) {
      return (ok: false, message: 'This app build is not configured.');
    }
    final publicKey = await platform.ensureInstallationKey();
    final fp = installationFingerprint(publicKey);
    final result = verifyActivationToken(
      token: rawToken,
      issuerPublicKey: issuer,
      expectedClientId: config.clientId,
      deviceFingerprint: fp,
      now: now(),
    );
    if (!result.isValid) {
      return (ok: false, message: describeActivationStatus(result.status));
    }
    if (!await _proveKeyPresent(publicKey)) {
      return (
        ok: false,
        message:
            'This phone\'s security key could not be used. Restart the '
            'app and try again.',
      );
    }
    tokens.writeToken(rawToken.trim().replaceAll(RegExp(r'\s'), ''));
    return (ok: true, message: 'Activated. Thank you!');
  }
}
