import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Static guards for the privacy rules. They read the source tree, so a
/// future change that adds logging, networking or cloud backup fails CI.
void main() {
  Iterable<File> dartFiles(String dir) =>
      Directory(dir)
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'));

  test('app code never logs (no print/debugPrint/log/developer)', () {
    final offenders = <String>[];
    final pattern = RegExp(
      r'(^|[^\w.])(print|debugPrint|log)\s*\(|dart:developer',
    );
    for (final f in dartFiles('lib')) {
      final lines = f.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final l = lines[i].trim();
        if (l.startsWith('//')) continue;
        // main.dart replaces debugPrint with a no-op in release.
        if (l.startsWith('debugPrint = ')) continue;
        if (pattern.hasMatch(l)) offenders.add('${f.path}:${i + 1}: $l');
      }
    }
    expect(offenders, isEmpty);
  });

  test('app code makes no network calls', () {
    final banned = RegExp(
      r'''HttpClient|package:http/|dart:html|WebSocket|Socket\.connect|RawSocket|package:dio|firebase|analytics|crashlytics|sentry''',
      caseSensitive: false,
    );
    final offenders = [
      for (final f in [
        ...dartFiles('lib'),
        ...dartFiles('packages/bcr_activation/lib'),
      ])
        if (banned.hasMatch(f.readAsStringSync())) f.path,
    ];
    expect(offenders, isEmpty);
  });

  test('pubspec has no analytics, crash-reporting or cloud dependencies', () {
    final pub = File('pubspec.yaml').readAsStringSync().toLowerCase();
    for (final bad in [
      'firebase',
      'sentry',
      'crashlytics',
      'analytics',
      'http:',
      'dio:',
      'supabase',
      'ads',
    ]) {
      expect(pub.contains('\n  $bad'), isFalse, reason: bad);
    }
  });

  test('Android: no INTERNET in release, backups and transfer excluded', () {
    final main = File('android/app/src/main/AndroidManifest.xml')
        .readAsStringSync();
    expect(main, contains('android.permission.INTERNET" tools:node="remove"'));
    expect(main, contains('android:allowBackup="false"'));
    expect(main, contains('@xml/data_extraction_rules'));
    expect(main, contains('@xml/backup_rules'));
    final rules = File('android/app/src/main/res/xml/data_extraction_rules.xml')
        .readAsStringSync();
    expect(rules, contains('<cloud-backup>'));
    expect(rules, contains('<device-transfer>'));
    final kt = File(
      'android/app/src/main/kotlin/com/bcr/dailyexpense/MainActivity.kt',
    ).readAsStringSync();
    expect(kt, contains('FLAG_SECURE'));
    expect(kt, isNot(contains('Log.')));
  });

  test('iOS: no iCloud entitlements, Face ID reason set, files excluded from backup', () {
    final ents = Directory('ios/Runner')
        .listSync()
        .where((e) => e.path.endsWith('.entitlements'))
        .map((e) => File(e.path).readAsStringSync())
        .join();
    expect(ents.contains('icloud'), isFalse);
    expect(ents.contains('CloudKit'), isFalse);
    final plist = File('ios/Runner/Info.plist').readAsStringSync();
    expect(plist, contains('NSFaceIDUsageDescription'));
    expect(plist, isNot(contains('NSAllowsArbitraryLoads')));
    final swift = File('ios/Runner/AppDelegate.swift').readAsStringSync();
    expect(swift, contains('isExcludedFromBackup = true'));
    expect(swift, contains('kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly'));
    expect(swift, contains('kSecAttrSynchronizable as String: false'));
  });

  test('database key storage is device-only and never auto-reset', () {
    final src = File('lib/platform/db_key_store.dart').readAsStringSync();
    expect(src, contains('resetOnError: false'));
    expect(src, contains('KeychainAccessibility.first_unlock_this_device'));
    expect(src, contains('synchronizable: false'));
  });

  test('SQLCipher is selected and no destructive migration exists', () {
    expect(
      File('pubspec.yaml').readAsStringSync(),
      contains('source: sqlcipher'),
    );
    final mig = File('lib/data/migrations.dart')
        .readAsStringSync()
        .toUpperCase();
    expect(mig.contains('DROP TABLE'), isFalse);
    expect(mig.contains('DELETE FROM'), isFalse);
  });

  test('no secrets committed: no private keys or keystores in the repo', () {
    final offenders = <String>[];
    for (final e in Directory(
      '.',
    ).listSync(recursive: true, followLinks: false)) {
      final p = e.path.replaceAll('\\', '/');
      if (p.contains('/build/') ||
          p.contains('/.dart_tool/') ||
          p.contains('/test/')) {
        continue;
      }
      if (e is! File) continue;
      if (RegExp(r'\.(jks|keystore|p12|mobileprovision)$').hasMatch(p) ||
          p.endsWith('key.properties')) {
        offenders.add(p);
      } else if (RegExp(r'\.(pem|json|dart|yaml|md|properties)$').hasMatch(p)) {
        final text = e.readAsStringSync();
        if (text.contains('-----BEGIN EC PRIVATE KEY-----\nM') ||
            text.contains('-----BEGIN PRIVATE KEY-----\nM')) {
          offenders.add(p);
        }
      }
    }
    expect(offenders, isEmpty);
  });
}
