import 'package:sqlite3/sqlite3.dart';

enum FailureKind {
  storageFull,
  keyUnavailable,
  encryptionUnavailable,
  wrongKeyOrCorrupt,
  newerSchema,
  notFound,
  categoryInactive,
  validation,
  unknown,
}

/// A failure with a message that is safe to show the user. Messages never
/// contain expense amounts, remarks or other record content.
class AppFailure implements Exception {
  const AppFailure(this.kind, this.userMessage);

  final FailureKind kind;
  final String userMessage;

  @override
  String toString() => 'AppFailure(${kind.name})';
}

// SQLite primary result codes (https://sqlite.org/rescode.html).
const _sqliteCorrupt = 11;
const _sqliteFull = 13;
const _sqliteIoErr = 10;
const _sqliteNotADb = 26;

AppFailure mapSqliteError(SqliteException e) {
  final primary = e.extendedResultCode & 0xff;
  switch (primary) {
    case _sqliteFull:
      return const AppFailure(
        FailureKind.storageFull,
        'Your phone is out of storage. Free up some space and try again. '
        'Nothing was saved.',
      );
    case _sqliteIoErr:
      return const AppFailure(
        FailureKind.storageFull,
        'The phone could not write to storage. Free up some space, restart '
        'the app and try again. Nothing was saved.',
      );
    case _sqliteNotADb:
    case _sqliteCorrupt:
      return const AppFailure(
        FailureKind.wrongKeyOrCorrupt,
        'The expense database could not be opened with this phone\'s key.',
      );
    default:
      return const AppFailure(
        FailureKind.unknown,
        'Something went wrong while saving. Nothing was changed. Please try '
        'again.',
      );
  }
}
