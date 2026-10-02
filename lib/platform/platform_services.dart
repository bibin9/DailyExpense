import 'package:flutter/services.dart';

/// Native capabilities implemented in MainActivity.kt (Android) and
/// PlatformBridge.swift (iOS). Kept deliberately small.
abstract interface class PlatformServices {
  /// Creates the per-installation P-256 signing key in Android Keystore /
  /// iOS Secure Enclave (or device-only Keychain) if it does not exist, and
  /// returns its public key (SPKI DER or raw X9.63 point).
  Future<Uint8List> ensureInstallationKey();

  /// Public key, or null if the key does not exist on this device.
  Future<Uint8List?> installationPublicKey();

  /// ECDSA-SHA256 signature (DER) made inside the keystore.
  Future<Uint8List> signWithInstallationKey(Uint8List data);

  Future<void> deleteInstallationKey();

  /// e.g. "StrongBox", "TEE", "Secure Enclave", "Keychain (software)".
  Future<String> installationKeyProtection();

  /// Marks a file or directory as excluded from iCloud/iTunes backup (iOS).
  /// Android relies on the manifest backup rules and returns true.
  Future<bool> excludeFromBackup(String path);

  /// Bytes available to this app on the volume holding [path].
  Future<int?> freeBytes(String path);

  /// Android FLAG_SECURE (blocks screenshots and recent-apps preview).
  Future<void> setSecureScreen(bool secure);

  /// Shows the system "save as" sheet (Android document picker / iOS Files)
  /// and copies [sourcePath] to the place the user chooses. Returns false if
  /// the user cancelled. The app itself never uploads anything.
  Future<bool> saveFileAs({
    required String sourcePath,
    required String fileName,
  });

  /// Shows the system file picker and copies the chosen file to
  /// [destinationPath]. Returns false if the user cancelled.
  Future<bool> pickFile({required String destinationPath});
}

class MethodChannelPlatformServices implements PlatformServices {
  static const _channel = MethodChannel('com.bcr.dailyexpense/platform');

  @override
  Future<Uint8List> ensureInstallationKey() async =>
      (await _channel.invokeMethod<Uint8List>('installKey.ensure'))!;

  @override
  Future<Uint8List?> installationPublicKey() =>
      _channel.invokeMethod<Uint8List>('installKey.publicKey');

  @override
  Future<Uint8List> signWithInstallationKey(Uint8List data) async =>
      (await _channel.invokeMethod<Uint8List>('installKey.sign', data))!;

  @override
  Future<void> deleteInstallationKey() =>
      _channel.invokeMethod<void>('installKey.delete');

  @override
  Future<String> installationKeyProtection() async =>
      (await _channel.invokeMethod<String>('installKey.protection')) ??
      'unknown';

  @override
  Future<bool> excludeFromBackup(String path) async =>
      (await _channel.invokeMethod<bool>('storage.excludeFromBackup', path)) ??
      false;

  @override
  Future<int?> freeBytes(String path) =>
      _channel.invokeMethod<int>('storage.freeBytes', path);

  @override
  Future<void> setSecureScreen(bool secure) =>
      _channel.invokeMethod<void>('window.setSecure', secure);

  @override
  Future<bool> saveFileAs({
    required String sourcePath,
    required String fileName,
  }) async =>
      (await _channel.invokeMethod<bool>('file.saveAs', {
        'source': sourcePath,
        'name': fileName,
      })) ??
      false;

  @override
  Future<bool> pickFile({required String destinationPath}) async =>
      (await _channel.invokeMethod<bool>('file.pick', destinationPath)) ??
      false;
}
