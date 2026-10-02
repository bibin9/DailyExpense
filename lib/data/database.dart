import 'dart:io';
import 'dart:typed_data';

import 'package:sqlite3/sqlite3.dart';

import 'failures.dart';
import 'migrations.dart';

/// Encrypted SQLite (SQLCipher) database.
///
/// The key is 32 random bytes passed as a raw key (`x'…'`), so no password
/// derivation runs at start-up. The database lives in app-private, durable
/// storage (never a cache directory).
class AppDatabase {
  AppDatabase._(this.raw, this.path);

  final Database raw;
  final String path;
  int _savepoint = 0;

  static const fileName = 'expenses.db';

  /// Opens (or creates) the database, verifies encryption is active and the
  /// key is correct, then applies pending migrations.
  static AppDatabase open({
    required String path,
    required Uint8List key,
    required int nowUtcMs,
  }) {
    if (key.length != 32) {
      throw const AppFailure(
        FailureKind.keyUnavailable,
        'The database key is invalid.',
      );
    }
    final existed = File(path).existsSync();
    final db = sqlite3.open(path);
    try {
      // Keep SQLCipher quiet in system logs (logcat/Console).
      db.execute('PRAGMA cipher_log_level = NONE;');
      final hex = key.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
      db.execute("PRAGMA key = \"x'$hex'\";");

      // Fail closed: if this build is not SQLCipher, refuse to continue
      // rather than silently writing an unencrypted database.
      final cipher = db.select('PRAGMA cipher_version;');
      final version = cipher.isEmpty ? null : cipher.first.values.first;
      if (version is! String || version.isEmpty) {
        throw const AppFailure(
          FailureKind.encryptionUnavailable,
          'This build of the app does not include database encryption, so '
          'it will not store expenses. Please install an official build.',
        );
      }

      // Reading the schema fails with SQLITE_NOTADB if the key is wrong.
      db.select('SELECT count(*) FROM sqlite_master;');

      db.execute('PRAGMA foreign_keys = ON;');
      db.execute('PRAGMA journal_mode = DELETE;');
      db.execute('PRAGMA synchronous = FULL;');
      db.execute('PRAGMA secure_delete = ON;');
      db.execute('PRAGMA temp_store = MEMORY;');

      if (existed) _copyBeforeMigrationIfNeeded(db, path);
      runMigrations(db, nowUtcMs: nowUtcMs);
      return AppDatabase._(db, path);
    } on SqliteException catch (e) {
      db.close();
      throw mapSqliteError(e);
    } catch (_) {
      db.close();
      rethrow;
    }
  }

  /// Before upgrading an existing schema, keep a byte-for-byte copy (still
  /// encrypted) next to the database so a failed upgrade can be recovered
  /// by support. Only the most recent copy is kept.
  static void _copyBeforeMigrationIfNeeded(Database db, String path) {
    final current = db.userVersion;
    if (current == 0 || current >= latestSchemaVersion) return;
    final copy = File('$path.pre-v$latestSchemaVersion.bak');
    if (!copy.existsSync()) File(path).copySync(copy.path);
  }

  int get schemaVersion => raw.userVersion;

  String cipherVersion() =>
      raw.select('PRAGMA cipher_version;').first.values.first as String;

  /// Runs [action] in an IMMEDIATE transaction. Either everything commits or
  /// nothing does; SQLite's rollback journal protects the file if the phone
  /// runs out of space or power mid-write.
  T transaction<T>(T Function() action) {
    if (!raw.autocommit) {
      // Already inside a transaction: nest with a savepoint.
      final name = 'sp${_savepoint++}';
      raw.execute('SAVEPOINT $name;');
      try {
        final result = action();
        raw.execute('RELEASE $name;');
        return result;
      } catch (_) {
        raw.execute('ROLLBACK TO $name;');
        raw.execute('RELEASE $name;');
        rethrow;
      }
    }
    raw.execute('BEGIN IMMEDIATE;');
    try {
      final result = action();
      raw.execute('COMMIT;');
      return result;
    } catch (_) {
      if (!raw.autocommit) raw.execute('ROLLBACK;');
      rethrow;
    }
  }

  int fileSizeBytes() {
    final f = File(path);
    return f.existsSync() ? f.lengthSync() : 0;
  }

  void close() => raw.close();
}
