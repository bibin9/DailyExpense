import 'package:local_auth/local_auth.dart';

enum AuthOutcome {
  success,
  cancelled,

  /// Too many attempts; user must wait or unlock the phone with the PIN.
  lockedOut,

  /// The phone has no screen lock (PIN/pattern/password/passcode).
  noDeviceSecurity,

  /// Prompt could not be shown right now (e.g. app in background).
  unavailable,
  failed,
}

abstract interface class DeviceAuthenticator {
  /// True if the phone has a screen lock (biometric enrolment optional).
  Future<bool> hasDeviceSecurity();
  Future<AuthOutcome> authenticate(String reason);
}

/// Biometric with automatic fallback to the device PIN/pattern/passcode
/// (`biometricOnly: false`). There is no app-specific PIN.
class LocalAuthAuthenticator implements DeviceAuthenticator {
  LocalAuthAuthenticator([LocalAuthentication? auth])
    : _auth = auth ?? LocalAuthentication();

  final LocalAuthentication _auth;

  @override
  Future<bool> hasDeviceSecurity() async {
    try {
      return await _auth.isDeviceSupported();
    } on Object {
      return false;
    }
  }

  @override
  Future<AuthOutcome> authenticate(String reason) async {
    try {
      final ok = await _auth.authenticate(
        localizedReason: reason,
        biometricOnly: false,
        persistAcrossBackgrounding: true,
      );
      return ok ? AuthOutcome.success : AuthOutcome.cancelled;
    } on LocalAuthException catch (e) {
      return mapAuthError(e.code);
    } on Object {
      return AuthOutcome.failed;
    }
  }
}

AuthOutcome mapAuthError(LocalAuthExceptionCode code) => switch (code) {
  LocalAuthExceptionCode.userCanceled ||
  LocalAuthExceptionCode.systemCanceled ||
  LocalAuthExceptionCode.userRequestedFallback ||
  LocalAuthExceptionCode.timeout => AuthOutcome.cancelled,
  LocalAuthExceptionCode.temporaryLockout ||
  LocalAuthExceptionCode.biometricLockout => AuthOutcome.lockedOut,
  LocalAuthExceptionCode.noCredentialsSet => AuthOutcome.noDeviceSecurity,
  LocalAuthExceptionCode.authInProgress ||
  LocalAuthExceptionCode.uiUnavailable => AuthOutcome.unavailable,
  _ => AuthOutcome.failed,
};

String describeAuthOutcome(AuthOutcome o) => switch (o) {
  AuthOutcome.success => '',
  AuthOutcome.cancelled => 'Unlock was cancelled. Tap Unlock to try again.',
  AuthOutcome.lockedOut =>
    'Too many attempts. Wait a little, or unlock your phone with its PIN, '
        'then tap Unlock again.',
  AuthOutcome.noDeviceSecurity =>
    'Your phone has no screen lock. Set up a PIN, pattern or password first.',
  AuthOutcome.unavailable => 'Unlock is not available right now. Tap Unlock.',
  AuthOutcome.failed => 'Could not verify it is you. Tap Unlock to try again.',
};
