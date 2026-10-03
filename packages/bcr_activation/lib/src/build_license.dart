import 'dart:convert';
import 'dart:typed_data';

import 'codes.dart';
import 'p256.dart';

/// Company licence embedded in a client's build ("pre-activated build").
///
/// JWS compact serialization, alg ES256, typ `det-build-license`, signed with
/// the client's issuer key by det_admin. Payload:
/// `{"v":1,"cid":"<client-id>","iat":<unix s>,"exp":<unix s, optional>}`.
///
/// Every phone running that build is licensed; there is no per-phone step.
/// The token is not secret (it ships inside the APK): its signature only
/// proves BCR issued it for that client and when it ends.
const buildLicenseType = 'det-build-license';
const buildLicenseVersion = 1;

class BuildLicense {
  BuildLicense({
    required this.clientId,
    required this.issuedAt,
    this.expiresAt,
  });

  final String clientId;
  final DateTime issuedAt;

  /// Null = no expiry.
  final DateTime? expiresAt;

  Map<String, Object?> toJson() => {
    'v': buildLicenseVersion,
    'cid': clientId,
    'iat': issuedAt.toUtc().millisecondsSinceEpoch ~/ 1000,
    if (expiresAt != null)
      'exp': expiresAt!.toUtc().millisecondsSinceEpoch ~/ 1000,
  };

  static BuildLicense fromJson(Map<String, Object?> json) {
    if (json['v'] != buildLicenseVersion) {
      throw const FormatException('Unsupported licence version');
    }
    DateTime ts(Object? v) =>
        DateTime.fromMillisecondsSinceEpoch((v! as int) * 1000, isUtc: true);
    return BuildLicense(
      clientId: json['cid']! as String,
      issuedAt: ts(json['iat']),
      expiresAt: json['exp'] == null ? null : ts(json['exp']),
    );
  }
}

String signBuildLicense(BuildLicense licence, P256KeyPair issuer) {
  final header = base64UrlNoPad(
    utf8.encode(jsonEncode({'alg': 'ES256', 'typ': buildLicenseType})),
  );
  final payload = base64UrlNoPad(utf8.encode(jsonEncode(licence.toJson())));
  final input = '$header.$payload';
  return '$input.${base64UrlNoPad(issuer.signRaw(ascii.encode(input)))}';
}

enum BuildLicenseStatus { valid, malformed, badSignature, wrongClient, expired }

class BuildLicenseCheck {
  const BuildLicenseCheck(this.status, [this.licence]);
  final BuildLicenseStatus status;
  final BuildLicense? licence;
  bool get isValid => status == BuildLicenseStatus.valid;
}

/// Signature first, then client and expiry. Never throws.
BuildLicenseCheck verifyBuildLicense({
  required String token,
  required Uint8List issuerPublicKey,
  required String expectedClientId,
  required DateTime now,
}) {
  final parts = token.trim().replaceAll(RegExp(r'\s'), '').split('.');
  if (parts.length != 3) {
    return const BuildLicenseCheck(BuildLicenseStatus.malformed);
  }
  try {
    final header = (jsonDecode(
      utf8.decode(base64UrlDecodeLenient(parts[0])),
    ) as Map).cast<String, Object?>();
    if (header['alg'] != 'ES256' || header['typ'] != buildLicenseType) {
      return const BuildLicenseCheck(BuildLicenseStatus.malformed);
    }
    if (!verifyP256Raw(
      issuerPublicKey,
      ascii.encode('${parts[0]}.${parts[1]}'),
      base64UrlDecodeLenient(parts[2]),
    )) {
      return const BuildLicenseCheck(BuildLicenseStatus.badSignature);
    }
    final licence = BuildLicense.fromJson(
      (jsonDecode(utf8.decode(base64UrlDecodeLenient(parts[1]))) as Map)
          .cast<String, Object?>(),
    );
    if (licence.clientId != expectedClientId) {
      return BuildLicenseCheck(BuildLicenseStatus.wrongClient, licence);
    }
    final exp = licence.expiresAt;
    if (exp != null && !now.toUtc().isBefore(exp)) {
      return BuildLicenseCheck(BuildLicenseStatus.expired, licence);
    }
    return BuildLicenseCheck(BuildLicenseStatus.valid, licence);
  } on Object {
    return const BuildLicenseCheck(BuildLicenseStatus.malformed);
  }
}
