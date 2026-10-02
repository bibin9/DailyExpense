import 'dart:io';
import 'dart:typed_data';

import 'package:characters/characters.dart';
import 'package:sqlite3/sqlite3.dart';

import '../core/local_date.dart';
import 'database.dart';
import 'failures.dart';
import 'migrations.dart';

/// Password-protected backup files for moving records to a new phone.
///
/// A backup is a SQLCipher database encrypted with a key derived from the
/// user's password (SQLCipher 4 defaults: PBKDF2-HMAC-SHA512, 256,000
/// iterations, random per-file salt, AES-256 + HMAC-SHA512 per page). It
/// never contains the activation token: every phone is activated on its own.
///
/// The device database key cannot be exported (it lives in the phone's
/// keystore), which is why a separate password is needed.

const backupFileExtension = 'detbak';
const backupFormatVersion = '1';
const minBackupPasswordLength = 8;
const maxImportBytes = 512 * 1024 * 1024;

/// Meta keys inside the main database.
const metaLastBackupAt = 'last_backup_at';
const metaBackupReminderSnoozedUntil = 'backup_reminder_snoozed_until';

/// Meta keys inside a backup file.
const _metaBackupFormat = 'backup_format';
const _metaBackupCreatedAt = 'backup_created_at';

class BackupInfo {
  const BackupInfo({
    required this.createdAtUtcMs,
    required this.schemaVersion,
    required this.expenseCount,
    required this.categoryCount,
    required this.totalFils,
    this.firstDate,
    this.lastDate,
  });

  final int createdAtUtcMs;
  final int schemaVersion;
  final int expenseCount;
  final int categoryCount;
  final int totalFils;
  final LocalDate? firstDate;
  final LocalDate? lastDate;
}

String? validateBackupPassword(String password, String confirmation) {
  if (password.characters.length < minBackupPasswordLength) {
    return 'Use at least $minBackupPasswordLength characters.';
  }
  if (password != confirmation) return 'The two passwords do not match.';
  return null;
}

String _hex(Uint8List key) =>
    key.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

const _wrongPassword = AppFailure(
  FailureKind.validation,
  'The password is wrong, or this is not a Daily Expense Tracker backup.',
);

/// Opens a backup file read-only-in-spirit with [password]. Throws
/// [AppFailure] for a wrong password or a file that is not a backup.
Database _openBackup(String path, String password) {
  final f = File(path);
  if (!f.existsSync()) {
    throw const AppFailure(
      FailureKind.notFound,
      'The backup file was not found.',
    );
  }
  if (f.lengthSync() > maxImportBytes) {
    throw const AppFailure(
      FailureKind.validation,
      'This file is too large to be a Daily Expense Tracker backup.',
    );
  }
  final db = sqlite3.open(path);
  try {
    db.execute('PRAGMA cipher_log_level = NONE;');
    db.execute('PRAGMA key = ${_sqlString(password)};');
    try {
      db.select('SELECT count(*) FROM sqlite_master;');
    } on SqliteException {
      throw _wrongPassword;
    }
    final format = db.select(
      "SELECT value FROM app_meta WHERE key = '$_metaBackupFormat';",
    );
    if (format.isEmpty || format.first['value'] != backupFormatVersion) {
      throw _wrongPassword;
    }
    if (db.userVersion > latestSchemaVersion) {
      throw const AppFailure(
        FailureKind.newerSchema,
        'This backup was made by a newer version of the app. Install the '
        'latest version on this phone first.',
      );
    }
    return db;
  } on SqliteException {
    db.close();
    throw _wrongPassword;
  } catch (_) {
    db.close();
    rethrow;
  }
}

/// SQL string literal (single quotes doubled). Used only for PRAGMA key /
/// ATTACH KEY, which do not accept bound parameters in every build.
String _sqlString(String s) => "'${s.replaceAll("'", "''")}'";

class BackupService {
  BackupService(this._db);

  final AppDatabase _db;

  /// Writes an encrypted backup of everything except the activation token
  /// to [outPath] (a temporary file the caller then hands to the system
  /// "save as" sheet). Verifies the file by reopening it before returning.
  BackupInfo createBackup({
    required String outPath,
    required String password,
    required int nowUtcMs,
  }) {
    if (password.characters.length < minBackupPasswordLength) {
      throw const AppFailure(
        FailureKind.validation,
        'Use at least $minBackupPasswordLength characters.',
      );
    }
    final out = File(outPath);
    if (out.existsSync()) out.deleteSync();
    final raw = _db.raw;
    try {
      raw.execute(
        'ATTACH DATABASE ${_sqlString(outPath)} AS bk KEY ${_sqlString(password)};',
      );
      try {
        raw.select("SELECT sqlcipher_export('bk');");
        raw.execute('PRAGMA bk.user_version = ${raw.userVersion};');
        raw.execute(
          "DELETE FROM bk.app_meta WHERE key IN "
          "('activation_token', '$metaLastBackupAt', '$metaBackupReminderSnoozedUntil');",
        );
        raw.execute(
          'INSERT OR REPLACE INTO bk.app_meta (key, value) VALUES (?, ?), (?, ?);',
          [
            _metaBackupFormat,
            backupFormatVersion,
            _metaBackupCreatedAt,
            '$nowUtcMs',
          ],
        );
      } finally {
        raw.execute('DETACH DATABASE bk;');
      }
      final info = inspectBackup(outPath, password);
      final live = raw
          .select(
            'SELECT COUNT(*) AS n, COALESCE(SUM(amount_fils), 0) AS t FROM expenses;',
          )
          .first;
      if (info.expenseCount != live['n'] || info.totalFils != live['t']) {
        throw const AppFailure(
          FailureKind.unknown,
          'The backup could not be verified. Please try again.',
        );
      }
      raw.execute(
        'INSERT INTO app_meta (key, value) VALUES (?, ?) '
        'ON CONFLICT(key) DO UPDATE SET value = excluded.value;',
        [metaLastBackupAt, '$nowUtcMs'],
      );
      return info;
    } on SqliteException catch (e) {
      if (out.existsSync()) out.deleteSync();
      throw mapSqliteError(e);
    } catch (_) {
      if (out.existsSync()) out.deleteSync();
      rethrow;
    }
  }

  /// Reads summary information from a backup (checks the password).
  static BackupInfo inspectBackup(String path, String password) {
    final db = _openBackup(path, password);
    try {
      final ok = db.select('PRAGMA cipher_integrity_check;');
      if (ok.isNotEmpty) {
        throw const AppFailure(
          FailureKind.wrongKeyOrCorrupt,
          'This backup file is damaged and cannot be restored.',
        );
      }
      final e = db
          .select(
            'SELECT COUNT(*) AS n, COALESCE(SUM(amount_fils), 0) AS t, '
            'MIN(local_date) AS a, MAX(local_date) AS b FROM expenses;',
          )
          .first;
      final c = db.select('SELECT COUNT(*) AS n FROM categories;').first;
      final created = db.select(
        "SELECT value FROM app_meta WHERE key = '$_metaBackupCreatedAt';",
      );
      return BackupInfo(
        createdAtUtcMs: created.isEmpty
            ? 0
            : int.parse(created.first['value'] as String),
        schemaVersion: db.userVersion,
        expenseCount: e['n'] as int,
        categoryCount: c['n'] as int,
        totalFils: e['t'] as int,
        firstDate: e['a'] == null ? null : LocalDate.parse(e['a'] as String),
        lastDate: e['b'] == null ? null : LocalDate.parse(e['b'] as String),
      );
    } on SqliteException {
      throw const AppFailure(
        FailureKind.wrongKeyOrCorrupt,
        'This backup file is damaged and cannot be restored.',
      );
    } finally {
      db.close();
    }
  }

  /// Re-encrypts a backup with this phone's database key into [targetPath]
  /// (which must not exist). Migrations are applied by AppDatabase.open
  /// afterwards. The caller swaps files only after this fully succeeds.
  static BackupInfo rebuildForDevice({
    required String backupPath,
    required String password,
    required String targetPath,
    required Uint8List deviceKey,
  }) {
    final info = inspectBackup(backupPath, password);
    final target = File(targetPath);
    if (target.existsSync()) target.deleteSync();
    final db = _openBackup(backupPath, password);
    try {
      db.execute(
        "ATTACH DATABASE ${_sqlString(targetPath)} AS rt KEY \"x'${_hex(deviceKey)}'\";",
      );
      try {
        db.select("SELECT sqlcipher_export('rt');");
        db.execute('PRAGMA rt.user_version = ${db.userVersion};');
        db.execute(
          "DELETE FROM rt.app_meta WHERE key IN ('$_metaBackupFormat', '$_metaBackupCreatedAt');",
        );
      } finally {
        db.execute('DETACH DATABASE rt;');
      }
      return info;
    } on SqliteException catch (e) {
      if (target.existsSync()) target.deleteSync();
      throw mapSqliteError(e);
    } catch (_) {
      if (target.existsSync()) target.deleteSync();
      rethrow;
    } finally {
      db.close();
    }
  }
}

/// Monthly reminder: shown when there are records and the last backup (or,
/// if never backed up, the first record) is 30+ days old, unless snoozed.
bool shouldRemindBackup({
  required int expenseCount,
  required int? lastBackupUtcMs,
  required int? firstExpenseCreatedUtcMs,
  required int? snoozedUntilUtcMs,
  required int nowUtcMs,
}) {
  if (expenseCount == 0) return false;
  if (snoozedUntilUtcMs != null && nowUtcMs < snoozedUntilUtcMs) return false;
  final reference = lastBackupUtcMs ?? firstExpenseCreatedUtcMs;
  if (reference == null) return false;
  return nowUtcMs - reference >= const Duration(days: 30).inMilliseconds;
}
