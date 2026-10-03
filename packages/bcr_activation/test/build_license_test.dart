import 'dart:convert';
import 'dart:math';

import 'package:bcr_activation/bcr_activation.dart';
import 'package:test/test.dart';

void main() {
  final issuer = P256KeyPair.generate(Random(10));
  final other = P256KeyPair.generate(Random(11));
  final now = DateTime.utc(2026, 10, 3);

  BuildLicenseStatus check(
    String t, {
    String cid = 'insideout-casa',
    DateTime? at,
  }) => verifyBuildLicense(
    token: t,
    issuerPublicKey: issuer.spki,
    expectedClientId: cid,
    now: at ?? now,
  ).status;

  String make({
    DateTime? exp,
    P256KeyPair? by,
    String cid = 'insideout-casa',
  }) => signBuildLicense(
    BuildLicense(clientId: cid, issuedAt: now, expiresAt: exp),
    by ?? issuer,
  );

  test('valid licence without expiry', () {
    expect(check(make()), BuildLicenseStatus.valid);
    expect(check(make(), at: DateTime.utc(2099)), BuildLicenseStatus.valid);
  });

  test('expiry: valid before, expired from the expiry instant', () {
    final t = make(exp: DateTime.utc(2027, 1, 1));
    expect(
      check(t, at: DateTime.utc(2026, 12, 31, 23, 59)),
      BuildLicenseStatus.valid,
    );
    expect(check(t, at: DateTime.utc(2027, 1, 1)), BuildLicenseStatus.expired);
  });

  test('other client, other issuer, tampering and junk are refused', () {
    expect(check(make(cid: 'acme-co')), BuildLicenseStatus.wrongClient);
    expect(check(make(by: other)), BuildLicenseStatus.badSignature);
    final parts = make(exp: DateTime.utc(2027)).split('.');
    final payload =
        jsonDecode(utf8.decode(base64UrlDecodeLenient(parts[1]))) as Map;
    payload.remove('exp'); // try to remove the expiry
    final forged =
        '${parts[0]}.${base64UrlNoPad(utf8.encode(jsonEncode(payload)))}.${parts[2]}';
    expect(check(forged), BuildLicenseStatus.badSignature);
    for (final junk in ['', 'a.b.c', '...', make().substring(0, 40)]) {
      expect(check(junk), isNot(BuildLicenseStatus.valid));
    }
  });

  test('a per-phone activation token is not accepted as a company licence', () {
    final perPhone = signActivationToken(
      ActivationClaims(
        clientId: 'insideout-casa',
        fingerprint: installationFingerprint(other.spki),
        issuedAt: now,
      ),
      issuer,
    );
    expect(check(perPhone), BuildLicenseStatus.malformed);
  });
}
