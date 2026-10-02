import 'database.dart';

/// Small key/value settings stored inside the encrypted database.
class MetaRepository {
  MetaRepository(this._db);

  final AppDatabase _db;

  String? read(String key) {
    final rows = _db.raw.select('SELECT value FROM app_meta WHERE key = ?;', [
      key,
    ]);
    return rows.isEmpty ? null : rows.first['value'] as String;
  }

  void write(String key, String value) {
    _db.raw.execute(
      'INSERT INTO app_meta (key, value) VALUES (?, ?) '
      'ON CONFLICT(key) DO UPDATE SET value = excluded.value;',
      [key, value],
    );
  }

  void delete(String key) =>
      _db.raw.execute('DELETE FROM app_meta WHERE key = ?;', [key]);
}
