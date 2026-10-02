// Release gate for Daily Expense Tracker (BCR).
//
//   dart run tool/release_check.dart \
//     --apk build/app/outputs/flutter-apk/app-release.apk \
//     --config config/clients/insideout-casa.json
//
// Fails (exit 1) if the release APK:
//  * requests INTERNET or ACCESS_NETWORK_STATE,
//  * is debuggable or allows backup,
//  * lacks the backup/data-extraction rules,
//  * contains the development-bypass marker text (bypass not compiled out),
//  * or the client config is incomplete / requests the dev bypass / uses the
//    development issuer.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

final failures = <String>[];
void check(bool ok, String message) {
  stdout.writeln('${ok ? 'PASS' : 'FAIL'}  $message');
  if (!ok) failures.add(message);
}

void main(List<String> args) {
  String? opt(String name) {
    final i = args.indexOf('--$name');
    return i >= 0 && i + 1 < args.length ? args[i + 1] : null;
  }

  final apkPath = opt('apk') ?? 'build/app/outputs/flutter-apk/app-release.apk';
  final configPath = opt('config');

  if (configPath != null) _checkConfig(configPath);

  final apk = File(apkPath);
  check(apk.existsSync(), 'release APK exists at $apkPath');
  if (apk.existsSync()) _checkApk(apk);

  stdout.writeln();
  if (failures.isEmpty) {
    stdout.writeln('Release check passed.');
  } else {
    stdout.writeln('Release check FAILED (${failures.length}).');
    exitCode = 1;
  }
}

void _checkConfig(String path) {
  final f = File(path);
  check(f.existsSync(), 'client config $path exists');
  if (!f.existsSync()) return;
  final cfg = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
  check(
    (cfg['DET_CLIENT_ID'] as String? ?? '').isNotEmpty,
    'config has DET_CLIENT_ID',
  );
  check(
    (cfg['DET_ISSUER_PUBLIC_KEY'] as String? ?? '').length > 80,
    'config has issuer public key',
  );
  check(
    !cfg.containsKey('DET_DEV_BYPASS'),
    'config does not request DET_DEV_BYPASS',
  );
  check(
    !cfg.containsKey('DET_ALLOW_SCREENSHOTS'),
    'config does not allow screenshots',
  );
  check(
    cfg['DET_CLIENT_ID'] != 'bcr-dev',
    'config is not the development client',
  );
  check(
    !f.readAsStringSync().contains('PRIVATE'),
    'config contains no private key',
  );
}

void _checkApk(File apk) {
  final entries = readZip(apk.readAsBytesSync());

  final sdk =
      Platform.environment['ANDROID_HOME'] ??
      Platform.environment['ANDROID_SDK_ROOT'];
  String? aapt2;
  if (sdk != null) {
    final bt = Directory('$sdk/build-tools');
    if (bt.existsSync()) {
      final versions = bt.listSync().whereType<Directory>().toList()
        ..sort((a, b) => a.path.compareTo(b.path));
      for (final v in versions.reversed) {
        final exe = File('${v.path}/aapt2${Platform.isWindows ? '.exe' : ''}');
        if (exe.existsSync()) {
          aapt2 = exe.path;
          break;
        }
      }
    }
  }
  check(aapt2 != null, 'aapt2 found (set ANDROID_HOME)');
  if (aapt2 != null) {
    final r = Process.runSync(aapt2, [
      'dump',
      'xmltree',
      apk.path,
      '--file',
      'AndroidManifest.xml',
    ]);
    final xml = '${r.stdout}';
    check(r.exitCode == 0, 'manifest readable');
    check(
      !xml.contains('android.permission.INTERNET'),
      'no INTERNET permission',
    );
    check(
      !xml.contains('android.permission.ACCESS_NETWORK_STATE'),
      'no ACCESS_NETWORK_STATE permission',
    );
    check(
      !RegExp(r'debuggable\(0x0101000f\)=(true|\(type 0x12\)0xffffffff)')
          .hasMatch(xml),
      'not debuggable',
    );
    check(
      RegExp(r'allowBackup\(0x01010280\)=(false|\(type 0x12\)0x0\b)')
          .hasMatch(xml),
      'allowBackup=false',
    );
    check(xml.contains('dataExtractionRules'), 'dataExtractionRules declared');
    check(xml.contains('fullBackupContent'), 'fullBackupContent declared');
  }

  final libs = entries.keys.where((n) => n.endsWith('/libapp.so')).toList();
  check(libs.isNotEmpty, 'compiled Dart code (libapp.so) present');
  const markers = ['DEVELOPMENT BYPASS', 'DET_DEV_BYPASS'];
  for (final lib in libs) {
    final text = latin1.decode(entries[lib]!, allowInvalid: true);
    final utf16 = String.fromCharCodes(entries[lib]!);
    for (final m in markers) {
      check(!text.contains(m) && !utf16.contains(m), '"$m" absent from $lib');
    }
  }
}

/// Minimal ZIP reader (stored + deflate), enough for APKs.
Map<String, Uint8List> readZip(Uint8List b) {
  final bd = ByteData.sublistView(b);
  var eocd = b.length - 22;
  while (eocd >= 0 && bd.getUint32(eocd, Endian.little) != 0x06054b50) {
    eocd--;
  }
  if (eocd < 0) throw const FormatException('Not a zip file');
  final count = bd.getUint16(eocd + 10, Endian.little);
  var p = bd.getUint32(eocd + 16, Endian.little);
  final out = <String, Uint8List>{};
  for (var i = 0; i < count; i++) {
    final method = bd.getUint16(p + 10, Endian.little);
    final compSize = bd.getUint32(p + 20, Endian.little);
    final nameLen = bd.getUint16(p + 28, Endian.little);
    final extraLen = bd.getUint16(p + 30, Endian.little);
    final commentLen = bd.getUint16(p + 32, Endian.little);
    final local = bd.getUint32(p + 42, Endian.little);
    final name = utf8.decode(b.sublist(p + 46, p + 46 + nameLen));
    final lNameLen = bd.getUint16(local + 26, Endian.little);
    final lExtraLen = bd.getUint16(local + 28, Endian.little);
    final dataStart = local + 30 + lNameLen + lExtraLen;
    final data = b.sublist(dataStart, dataStart + compSize);
    if (name.endsWith('libapp.so') || name == 'AndroidManifest.xml') {
      out[name] = method == 0
          ? data
          : Uint8List.fromList(ZLibDecoder(raw: true).convert(data));
    } else {
      out[name] = Uint8List(0);
    }
    p += 46 + nameLen + extraLen + commentLen;
  }
  return out;
}
