import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Holds the random 256-bit database key.
abstract interface class DbKeyStore {
  Future<Uint8List?> read();
  Future<void> write(Uint8List key);
  Future<void> delete();
}

Uint8List generateDbKey([Random? random]) {
  final rnd = random ?? Random.secure();
  return Uint8List.fromList(List.generate(32, (_) => rnd.nextInt(256)));
}

/// flutter_secure_storage 11.x:
///  * Android: value encrypted with AES-GCM; the AES key is wrapped by an RSA
///    key that lives in Android Keystore. `resetOnError` is OFF — the
///    plugin's default would silently erase the key (and so every expense)
///    after a decryption error. We surface the error instead.
///  * iOS: Keychain item with `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`
///    and `synchronizable: false` — never synced to iCloud Keychain and not
///    restorable to a different device.
class SecureDbKeyStore implements DbKeyStore {
  SecureDbKeyStore([FlutterSecureStorage? storage])
    : _storage =
          storage ??
          const FlutterSecureStorage(
            aOptions: AndroidOptions(
              resetOnError: false,
              migrateOnAlgorithmChange: true,
              migrateWithBackup: true,
            ),
            iOptions: IOSOptions(
              accessibility: KeychainAccessibility.first_unlock_this_device,
              synchronizable: false,
              accountName: 'com.bcr.dailyexpense.dbkey',
            ),
          );

  static const _keyName = 'det.db.key.v1';
  final FlutterSecureStorage _storage;

  @override
  Future<Uint8List?> read() async {
    final v = await _storage.read(key: _keyName);
    if (v == null) return null;
    final bytes = base64.decode(v);
    return bytes.length == 32 ? bytes : null;
  }

  @override
  Future<void> write(Uint8List key) =>
      _storage.write(key: _keyName, value: base64.encode(key));

  @override
  Future<void> delete() => _storage.delete(key: _keyName);
}
