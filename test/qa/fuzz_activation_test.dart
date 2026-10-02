import 'dart:math';

import 'package:bcr_activation/bcr_activation.dart';
import 'package:flutter_test/flutter_test.dart';

/// QA: every single-character change to a valid activation code must be
/// rejected (or be a no-op base64 variant), and nothing may throw.
void main() {
  final issuer = P256KeyPair.generate(Random(1));
  final device = P256KeyPair.generate(Random(2));
  final fp = installationFingerprint(device.spki);
  final now = DateTime.utc(2026, 10, 2);
  final token = signActivationToken(
    ActivationClaims(
      clientId: 'insideout-casa',
      fingerprint: fp,
      issuedAt: now,
      label: 'QA',
    ),
    issuer,
  );

  ActivationStatus check(String t) => verifyActivationToken(
    token: t,
    issuerPublicKey: issuer.spki,
    expectedClientId: 'insideout-casa',
    deviceFingerprint: fp,
    now: now,
  ).status;

  test('original token is valid', () {
    expect(check(token), ActivationStatus.valid);
  });

  test('every single-character substitution is rejected', () {
    const b64 =
        'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_';
    var accepted = 0;
    for (var i = 0; i < token.length; i++) {
      if (token[i] == '.') continue;
      for (final c in ['A', 'z', '0', '_', '.']) {
        if (c == token[i]) continue;
        final t = token.replaceRange(i, i + 1, c);
        final s = check(t);
        if (s == ActivationStatus.valid) {
          // Only acceptable if it decodes to identical bytes (padding bits
          // of the final base64 character).
          final isLastCharOfSegment =
              i == token.length - 1 || token[i + 1] == '.';
          expect(
            isLastCharOfSegment && b64.contains(c),
            isTrue,
            reason: 'position $i accepted "$c"',
          );
          accepted++;
        }
      }
    }
    expect(accepted, lessThan(10));
  });

  test(
    'truncations, duplications and random garbage never validate or throw',
    () {
      for (var n = 0; n < token.length; n++) {
        expect(check(token.substring(0, n)), isNot(ActivationStatus.valid));
      }
      expect(check('$token$token'), isNot(ActivationStatus.valid));
      expect(check('$token.'), isNot(ActivationStatus.valid));
      final rnd = Random(5);
      for (var i = 0; i < 5000; i++) {
        final g = String.fromCharCodes(
          List.generate(rnd.nextInt(300), (_) => 32 + rnd.nextInt(95)),
        );
        expect(check(g), isNot(ActivationStatus.valid));
      }
    },
  );

  test('whitespace and line breaks from chat apps are tolerated', () {
    final wrapped = [
      for (var i = 0; i < token.length; i += 40)
        token.substring(i, min(i + 40, token.length)),
    ].join('\n ');
    expect(check('  $wrapped \n'), ActivationStatus.valid);
  });

  test(
    'request codes: random corruption is caught by the check characters',
    () {
      final code = ActivationRequest(
        clientId: 'insideout-casa',
        fingerprint: fp,
      ).encode();
      final rnd = Random(9);
      var caught = 0;
      for (var i = 0; i < 2000; i++) {
        final pos = code.lastIndexOf(':') - 1 - rnd.nextInt(52);
        final ch = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567'[rnd.nextInt(32)];
        if (code[pos] == ch) continue;
        final bad = code.replaceRange(pos, pos + 1, ch);
        try {
          ActivationRequest.parse(bad);
        } on FormatException {
          caught++;
          continue;
        }
        fail('corrupted request accepted: $bad');
      }
      expect(caught, greaterThan(1900));
    },
  );
}
