import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:bcr_activation/bcr_activation.dart';
import 'package:test/test.dart';

void main() {
  final rnd = Random(42); // deterministic test keys only
  final issuer = P256KeyPair.generate(rnd);
  final otherIssuer = P256KeyPair.generate(rnd);
  final deviceA = P256KeyPair.generate(rnd);
  final deviceB = P256KeyPair.generate(rnd);
  final now = DateTime.utc(2026, 10, 2, 10);
  const client = 'insideout-casa';

  String tokenFor(P256KeyPair device, {DateTime? exp, String cid = client}) =>
      signActivationToken(
        ActivationClaims(
          clientId: cid,
          fingerprint: installationFingerprint(device.spki),
          issuedAt: now,
          expiresAt: exp,
          label: 'Test phone',
        ),
        issuer,
      );

  ActivationCheck check(String token, P256KeyPair device, {Uint8List? key}) =>
      verifyActivationToken(
        token: token,
        issuerPublicKey: key ?? issuer.spki,
        expectedClientId: client,
        deviceFingerprint: installationFingerprint(device.spki),
        now: now,
      );

  test('valid token for the bound device is accepted', () {
    final result = check(tokenFor(deviceA), deviceA);
    expect(result.status, ActivationStatus.valid);
    expect(result.claims!.label, 'Test phone');
  });

  test('token for device A is rejected on device B', () {
    expect(
      check(tokenFor(deviceA), deviceB).status,
      ActivationStatus.wrongDevice,
    );
  });

  test('modified payload is rejected (signature no longer matches)', () {
    final parts = tokenFor(deviceA).split('.');
    final payload = jsonDecode(
      utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
    ) as Map<String, Object?>;
    payload['fp'] = installationFingerprint(deviceB.spki);
    final forged =
        '${parts[0]}.${base64UrlNoPad(utf8.encode(jsonEncode(payload)))}.${parts[2]}';
    expect(check(forged, deviceB).status, ActivationStatus.badSignature);
  });

  test('flipped signature byte is rejected', () {
    final parts = tokenFor(deviceA).split('.');
    final sig = base64UrlDecodeLenient(parts[2]);
    sig[10] ^= 0x01;
    final forged = '${parts[0]}.${parts[1]}.${base64UrlNoPad(sig)}';
    expect(check(forged, deviceA).status, ActivationStatus.badSignature);
  });

  test('token signed by a different issuer is rejected', () {
    final token = signActivationToken(
      ActivationClaims(
        clientId: client,
        fingerprint: installationFingerprint(deviceA.spki),
        issuedAt: now,
      ),
      otherIssuer,
    );
    expect(check(token, deviceA).status, ActivationStatus.badSignature);
  });

  test('alg other than ES256 is refused before any verification', () {
    final parts = tokenFor(deviceA).split('.');
    final none = base64UrlNoPad(
      utf8.encode(jsonEncode({'alg': 'none', 'typ': tokenType})),
    );
    expect(
      check('$none.${parts[1]}.', deviceA).status,
      ActivationStatus.unsupportedAlgorithm,
    );
  });

  test('token for another client is rejected', () {
    expect(
      check(tokenFor(deviceA, cid: 'other-client'), deviceA).status,
      ActivationStatus.wrongClient,
    );
  });

  test('expired token is rejected, unexpired accepted', () {
    expect(
      check(tokenFor(deviceA, exp: now), deviceA).status,
      ActivationStatus.expired,
    );
    expect(
      check(
        tokenFor(deviceA, exp: now.add(const Duration(days: 1))),
        deviceA,
      ).status,
      ActivationStatus.valid,
    );
  });

  test('garbage input is malformed, never throws', () {
    for (final t in ['', 'abc', 'a.b.c', '...', 'DETACT']) {
      expect(check(t, deviceA).isValid, isFalse);
    }
  });

  test('raw point and SPKI produce the same fingerprint', () {
    expect(
      installationFingerprint(deviceA.publicPoint),
      installationFingerprint(deviceA.spki),
    );
    expect(installationFingerprint(deviceA.spki), hasLength(52));
  });

  test('DER signatures (platform format) verify; tampered message fails', () {
    final msg = utf8.encode('det-proof-v1:challenge');
    final der = deviceA.signDer(msg);
    expect(verifyP256Der(deviceA.spki, msg, der), isTrue);
    expect(verifyP256Der(deviceB.spki, msg, der), isFalse);
    expect(verifyP256Der(deviceA.spki, utf8.encode('other'), der), isFalse);
  });

  test('off-curve public key is rejected', () {
    final bad = Uint8List.fromList(deviceA.publicPoint);
    bad[64] ^= 0x01;
    expect(() => installationFingerprint(bad), throwsFormatException);
  });

  group('request code', () {
    final fp = installationFingerprint(deviceA.spki);

    test('round-trips', () {
      final code = ActivationRequest(
        clientId: client,
        fingerprint: fp,
      ).encode();
      final parsed = ActivationRequest.parse(code);
      expect(parsed.clientId, client);
      expect(parsed.fingerprint, fp);
    });

    test('typo is caught by the check characters', () {
      final code = ActivationRequest(
        clientId: client,
        fingerprint: fp,
      ).encode();
      final i = code.indexOf(fp) + 5;
      final typo = code.replaceRange(i, i + 1, code[i] == 'A' ? 'B' : 'A');
      expect(() => ActivationRequest.parse(typo), throwsFormatException);
    });
  });

  test('private key PEM round-trips through SEC1 encoding', () {
    final der = encodeP256Sec1PrivateKey(
      issuer.privateScalar,
      issuer.publicPoint,
    );
    final pem = pemEncode('EC PRIVATE KEY', der);
    final back = P256KeyPair.fromPrivateScalar(
      parseP256PrivateKey(pemOrBase64Decode(pem)),
    );
    expect(back.publicPoint, issuer.publicPoint);
  });
}
