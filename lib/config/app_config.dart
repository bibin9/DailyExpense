import 'dart:convert';

import 'package:bcr_activation/bcr_activation.dart';
import 'package:flutter/foundation.dart';

/// Product identity. The product is the same for every client; client
/// branding and the activation issuer key come from
/// `--dart-define-from-file=config/clients/<client>.json`.
abstract final class Product {
  static const name = 'Daily Expense Tracker';
  static const vendorShort = 'BCR';
  static const vendorLong = 'BibinCutRiver';
  static const signature = 'Crafted by BCR';
  static const version = '1.0.0';
}

/// Decides whether the development activation bypass may be used.
/// Pure function so it is unit-tested; release and profile builds never
/// allow it regardless of what was requested.
bool devBypassAllowed({required bool isDebugBuild, required bool requested}) =>
    isDebugBuild && requested;

class AppConfig {
  const AppConfig({
    required this.clientId,
    required this.clientName,
    required this.issuerPublicKeyBase64,
  });

  static const AppConfig fromEnvironment = AppConfig(
    clientId: String.fromEnvironment('DET_CLIENT_ID'),
    clientName: String.fromEnvironment('DET_CLIENT_NAME'),
    issuerPublicKeyBase64: String.fromEnvironment('DET_ISSUER_PUBLIC_KEY'),
  );

  /// `kDebugMode` is a compile-time constant, so in release/profile builds
  /// this is `const false` and the bypass code is removed by the compiler.
  /// tool/release_check.dart verifies the marker text is absent from the
  /// release binary.
  static const bool devBypassActive =
      kDebugMode && bool.fromEnvironment('DET_DEV_BYPASS');

  final String clientId;
  final String clientName;
  final String issuerPublicKeyBase64;

  String get displayClientName => clientName.isEmpty ? clientId : clientName;

  /// Null if missing or not a valid P-256 public key.
  Uint8List? get issuerPublicKey {
    if (issuerPublicKeyBase64.isEmpty) return null;
    try {
      final bytes = base64.decode(issuerPublicKeyBase64);
      installationFingerprint(bytes); // validates it is a P-256 point
      return bytes;
    } on Object {
      return null;
    }
  }

  bool get isComplete => isValidClientId(clientId) && issuerPublicKey != null;
}
