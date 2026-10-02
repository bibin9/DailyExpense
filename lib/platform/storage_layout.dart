import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Where the app keeps its files.
///
/// `getApplicationSupportDirectory()`:
///  * Android: `/data/data/<pkg>/files` — app-private, durable, not a cache.
///  * iOS: `Library/Application Support` — durable; we additionally set
///    `isExcludedFromBackup` on our folder and every file in it.
class StorageLayout {
  StorageLayout(this.dataDir);

  final Directory dataDir;

  static Future<StorageLayout> resolve() async {
    final base = await getApplicationSupportDirectory();
    final dir = Directory('${base.path}${Platform.pathSeparator}det_data');
    return StorageLayout(dir);
  }

  String get databasePath => _child('expenses.db');

  /// Written after first successful start. App-private files are removed on
  /// uninstall on both platforms, but iOS Keychain items are not — so
  /// "keychain has items but no marker" means a reinstall.
  File get installMarker => File(_child('install.marker'));

  String _child(String name) => '${dataDir.path}${Platform.pathSeparator}$name';

  /// Every file in our folder (db, rollback journal, pre-migration copy).
  List<String> allPaths() => [
    dataDir.path,
    if (dataDir.existsSync())
      ...dataDir.listSync().whereType<File>().map((f) => f.path),
  ];
}
