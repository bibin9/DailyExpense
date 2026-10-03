import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:bcr_activation/bcr_activation.dart';
import 'package:det_admin/det_admin.dart';
import 'package:test/test.dart';

void main() {
  late Directory dir;
  late StringBuffer out;
  late Admin admin;
  final now = DateTime.utc(2026, 10, 2, 9);

  setUp(() {
    dir = Directory.systemTemp.createTempSync('det_admin_test');
    out = StringBuffer();
    admin = Admin(
      out: out,
      env: {'BCR_DET_ISSUER_DIR': dir.path},
      now: () => now,
    );
  });
  tearDown(() => dir.deleteSync(recursive: true));

  String requestFor(P256KeyPair device, [String client = 'insideout-casa']) =>
      ActivationRequest(
        clientId: client,
        fingerprint: installationFingerprint(device.spki),
      ).encode();

  test('init, write-config, sign and verify end to end', () {
    expect(admin.run(['init-issuer', '--client', 'insideout-casa']), 0);
    final cfgPath = '${dir.path}/cfg.json';
    expect(
      admin.run([
        'write-config', '--client', 'insideout-casa', //
        '--name', 'InsideOut Casa', '--out', cfgPath,
      ]),
      0,
    );
    final cfg = jsonDecode(File(cfgPath).readAsStringSync()) as Map;
    expect(cfg['DET_CLIENT_NAME'], 'InsideOut Casa');
    expect(cfg.toString(), isNot(contains('PRIVATE')));

    final device = P256KeyPair.generate(Random(1));
    out.clear();
    expect(
      admin.run([
        'sign', '--client', 'insideout-casa', //
        '--request', requestFor(device), '--label', 'Driver 1',
      ]),
      0,
    );
    final token = out
        .toString()
        .split('\n')
        .firstWhere((l) => l.split('.').length == 3 && l.length > 100);
    final check = verifyActivationToken(
      token: token,
      issuerPublicKey: base64.decode(cfg['DET_ISSUER_PUBLIC_KEY'] as String),
      expectedClientId: 'insideout-casa',
      deviceFingerprint: installationFingerprint(device.spki),
      now: now,
    );
    expect(check.status, ActivationStatus.valid);
    expect(check.claims!.label, 'Driver 1');
    expect(
      File('${dir.path}/insideout-casa.issued.csv').readAsStringSync(),
      contains(installationFingerprint(device.spki)),
    );

    expect(
      admin.run(['verify', '--client', 'insideout-casa', '--token', token]),
      0,
    );
  });

  test('refuses to overwrite an existing issuer key', () {
    admin.run(['init-issuer', '--client', 'acme-co']);
    expect(
      () => admin.run(['init-issuer', '--client', 'acme-co']),
      throwsA(isA<CliException>()),
    );
  });

  test('refuses to sign a request made for another client build', () {
    admin.run(['init-issuer', '--client', 'acme-co']);
    final device = P256KeyPair.generate(Random(2));
    expect(
      () => admin.run([
        'sign', '--client', 'acme-co', //
        '--request', requestFor(device, 'insideout-casa'),
      ]),
      throwsA(isA<CliException>()),
    );
  });

  test(
    'license writes a verifiable company licence; per-device removes it',
    () {
      admin.run(['init-issuer', '--client', 'insideout-casa']);
      final cfgPath = '${dir.path}/cfg.json';
      admin.run([
        'write-config', '--client', 'insideout-casa', //
        '--name', 'InsideOut Casa', '--out', cfgPath,
      ]);
      expect(
        admin.run([
          'license', '--client', 'insideout-casa', //
          '--config', cfgPath, '--until', '2027-12-31',
        ]),
        0,
      );
      final cfg = jsonDecode(File(cfgPath).readAsStringSync()) as Map;
      final pub = base64.decode(cfg['DET_ISSUER_PUBLIC_KEY'] as String);
      final token = cfg['DET_BUILD_LICENSE'] as String;
      BuildLicenseStatus at(DateTime t) => verifyBuildLicense(
        token: token,
        issuerPublicKey: pub,
        expectedClientId: 'insideout-casa',
        now: t,
      ).status;
      // Valid all of 31 Dec in the UAE (UTC+4), expired from 1 Jan 00:00 UAE.
      expect(at(DateTime.utc(2027, 12, 31, 19, 59)), BuildLicenseStatus.valid);
      expect(at(DateTime.utc(2027, 12, 31, 20, 0)), BuildLicenseStatus.expired);
      expect(cfg['DET_CLIENT_NAME'], 'InsideOut Casa'); // other keys kept

      expect(
        () => admin.run([
          'license', '--client', 'insideout-casa', //
          '--config', cfgPath, '--until', '2020-01-01',
        ]),
        throwsA(isA<CliException>()),
      );
      expect(
        () =>
            admin.run(['license', '--client', 'acme-co', '--config', cfgPath]),
        throwsA(isA<CliException>()),
      );

      admin.run([
        'per-device',
        '--client',
        'insideout-casa',
        '--config',
        cfgPath,
      ]);
      final after = jsonDecode(File(cfgPath).readAsStringSync()) as Map;
      expect(after.containsKey('DET_BUILD_LICENSE'), isFalse);
    },
  );
}
