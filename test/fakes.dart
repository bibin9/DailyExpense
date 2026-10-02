import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:bcr_activation/bcr_activation.dart';
import 'package:daily_expense_tracker/core/capture.dart';
import 'package:daily_expense_tracker/platform/db_key_store.dart';
import 'package:daily_expense_tracker/platform/platform_services.dart';
import 'package:daily_expense_tracker/security/device_auth.dart';

/// Software stand-in for the Keystore/Secure Enclave key, one per "device".
class FakePlatform implements PlatformServices {
  FakePlatform({int seed = 1}) : _rnd = Random(seed);

  final Random _rnd;
  P256KeyPair? key;
  int? free = 1 << 30;
  Completer<void>? freeBytesGate;
  final excluded = <String>[];
  int deleteCalls = 0;

  @override
  Future<Uint8List> ensureInstallationKey() async =>
      (key ??= P256KeyPair.generate(_rnd)).spki;

  @override
  Future<Uint8List?> installationPublicKey() async => key?.spki;

  @override
  Future<Uint8List> signWithInstallationKey(Uint8List data) async {
    final k = key;
    if (k == null) throw StateError('no key');
    return k.signDer(data);
  }

  @override
  Future<void> deleteInstallationKey() async {
    deleteCalls++;
    key = null;
  }

  @override
  Future<String> installationKeyProtection() async => 'test';

  @override
  Future<bool> excludeFromBackup(String path) async {
    excluded.add(path);
    return true;
  }

  @override
  Future<int?> freeBytes(String path) async {
    await freeBytesGate?.future;
    return free;
  }

  @override
  Future<void> setSecureScreen(bool secure) async {}

  /// Where "save as" copies to (null = user cancels).
  String? saveDestination;
  final saved = <String>[];

  /// File the user "picks" (null = user cancels).
  String? pickSource;

  @override
  Future<bool> saveFileAs({
    required String sourcePath,
    required String fileName,
  }) async {
    final dest = saveDestination;
    if (dest == null) return false;
    File(sourcePath).copySync(dest);
    saved.add(fileName);
    return true;
  }

  @override
  Future<bool> pickFile({required String destinationPath}) async {
    final src = pickSource;
    if (src == null) return false;
    File(src).copySync(destinationPath);
    return true;
  }
}

class MemoryKeyStore implements DbKeyStore {
  Uint8List? value;
  @override
  Future<void> delete() async => value = null;
  @override
  Future<Uint8List?> read() async => value;
  @override
  Future<void> write(Uint8List key) async => value = key;
}

class FakeAuth implements DeviceAuthenticator {
  bool secure = true;
  AuthOutcome next = AuthOutcome.success;
  int calls = 0;
  @override
  Future<AuthOutcome> authenticate(String reason) async {
    calls++;
    return next;
  }

  @override
  Future<bool> hasDeviceSecurity() async => secure;
}

class FixedClock implements Clock {
  FixedClock(this.value);
  DateTime value;
  @override
  DateTime now() => value;
}
