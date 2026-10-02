import 'dart:convert';
import 'dart:typed_data';

import 'codes.dart';
import 'p256.dart';

/// Activation token = JWS compact serialization, alg ES256 (ECDSA P-256 +
/// SHA-256, raw r||s signature), typ `det-activation`. Any JOSE library can
/// inspect it; the app accepts nothing but ES256 to avoid algorithm
/// confusion.
const tokenType = 'det-activation';
const tokenVersion = 1;

class ActivationClaims {
  ActivationClaims({
    required this.clientId,
    required this.fingerprint,
    required this.issuedAt,
    this.expiresAt,
    this.label,
    this.tokenId,
  });

  final String clientId;
  final String fingerprint;
  final DateTime issuedAt;
  final DateTime? expiresAt;
  final String? label;
  final String? tokenId;

  Map<String, Object?> toJson() => {
    'v': tokenVersion,
    'cid': clientId,
    'fp': fingerprint,
    'iat': issuedAt.toUtc().millisecondsSinceEpoch ~/ 1000,
    if (expiresAt != null)
      'exp': expiresAt!.toUtc().millisecondsSinceEpoch ~/ 1000,
    if (label != null && label!.isNotEmpty) 'lbl': label,
    if (tokenId != null) 'jti': tokenId,
  };

  static ActivationClaims fromJson(Map<String, Object?> json) {
    if (json['v'] != tokenVersion) {
      throw const FormatException('Unsupported token version');
    }
    DateTime ts(Object? v) =>
        DateTime.fromMillisecondsSinceEpoch((v! as int) * 1000, isUtc: true);
    return ActivationClaims(
      clientId: json['cid']! as String,
      fingerprint: json['fp']! as String,
      issuedAt: ts(json['iat']),
      expiresAt: json['exp'] == null ? null : ts(json['exp']),
      label: json['lbl'] as String?,
      tokenId: json['jti'] as String?,
    );
  }
}

/// Signs [claims] with the issuer key. Admin-side only.
String signActivationToken(ActivationClaims claims, P256KeyPair issuer) {
  final header = base64UrlNoPad(
    utf8.encode(jsonEncode({'alg': 'ES256', 'typ': tokenType})),
  );
  final payload = base64UrlNoPad(utf8.encode(jsonEncode(claims.toJson())));
  final signingInput = '$header.$payload';
  final sig = issuer.signRaw(ascii.encode(signingInput));
  return '$signingInput.${base64UrlNoPad(sig)}';
}

enum ActivationStatus {
  valid,
  malformed,
  unsupportedAlgorithm,
  badSignature,
  wrongClient,
  wrongDevice,
  expired,
}

class ActivationCheck {
  const ActivationCheck(this.status, [this.claims]);
  final ActivationStatus status;
  final ActivationClaims? claims;
  bool get isValid => status == ActivationStatus.valid;
}

/// Verifies signature first, then binding. Order matters: nothing from an
/// unauthenticated payload is trusted.
ActivationCheck verifyActivationToken({
  required String token,
  required Uint8List issuerPublicKey,
  required String expectedClientId,
  required String deviceFingerprint,
  required DateTime now,
}) {
  final parts = token.trim().replaceAll(RegExp(r'\s'), '').split('.');
  if (parts.length != 3) {
    return const ActivationCheck(ActivationStatus.malformed);
  }
  Map<String, Object?> header;
  Uint8List sig;
  try {
    header = (jsonDecode(utf8.decode(base64UrlDecodeLenient(parts[0]))) as Map)
        .cast<String, Object?>();
    sig = base64UrlDecodeLenient(parts[2]);
  } on Object {
    return const ActivationCheck(ActivationStatus.malformed);
  }
  if (header['alg'] != 'ES256' || header['typ'] != tokenType) {
    return const ActivationCheck(ActivationStatus.unsupportedAlgorithm);
  }
  if (!verifyP256Raw(
    issuerPublicKey,
    ascii.encode('${parts[0]}.${parts[1]}'),
    sig,
  )) {
    return const ActivationCheck(ActivationStatus.badSignature);
  }
  ActivationClaims claims;
  try {
    claims = ActivationClaims.fromJson(
      (jsonDecode(utf8.decode(base64UrlDecodeLenient(parts[1]))) as Map)
          .cast<String, Object?>(),
    );
  } on Object {
    return const ActivationCheck(ActivationStatus.malformed);
  }
  if (claims.clientId != expectedClientId) {
    return ActivationCheck(ActivationStatus.wrongClient, claims);
  }
  if (claims.fingerprint != deviceFingerprint) {
    return ActivationCheck(ActivationStatus.wrongDevice, claims);
  }
  final exp = claims.expiresAt;
  if (exp != null && !now.toUtc().isBefore(exp)) {
    return ActivationCheck(ActivationStatus.expired, claims);
  }
  return ActivationCheck(ActivationStatus.valid, claims);
}
