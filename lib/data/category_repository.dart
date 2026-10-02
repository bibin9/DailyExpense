import 'package:sqlite3/sqlite3.dart';

import '../domain/models.dart';
import '../domain/validation.dart';
import 'database.dart';
import 'failures.dart';

class CategoryRepository {
  CategoryRepository(this._db);

  final AppDatabase _db;

  static Category _map(Row r) => Category(
    id: r['id'] as int,
    name: r['name'] as String,
    isActive: r['is_active'] == 1,
    requiresRemark: r['requires_remark'] == 1,
    sortOrder: r['sort_order'] as int,
  );

  /// Active first, then inactive; each in the user's order.
  List<Category> all() => _db.raw
      .select(
        'SELECT * FROM categories ORDER BY is_active DESC, sort_order, id;',
      )
      .map(_map)
      .toList();

  List<Category> active() => _db.raw
      .select(
        'SELECT * FROM categories WHERE is_active = 1 ORDER BY sort_order, id;',
      )
      .map(_map)
      .toList();

  Category? byId(int id) {
    final rows = _db.raw.select('SELECT * FROM categories WHERE id = ?;', [id]);
    return rows.isEmpty ? null : _map(rows.first);
  }

  String _validateName(String name, {int? excludingId}) {
    final clean = cleanCategoryName(name);
    if (clean.isEmpty) {
      throw const AppFailure(FailureKind.validation, 'Enter a category name.');
    }
    if (clean.length > maxCategoryNameLength) {
      throw const AppFailure(
        FailureKind.validation,
        'Category names can be at most $maxCategoryNameLength characters.',
      );
    }
    final existing = _db.raw.select(
      'SELECT id, name, is_active FROM categories WHERE name_key = ? AND id != ?;',
      [categoryNameKey(clean), excludingId ?? -1],
    );
    if (existing.isNotEmpty) {
      final other = existing.first;
      throw AppFailure(
        FailureKind.validation,
        other['is_active'] == 1
            ? '"${other['name']}" already exists.'
            : '"${other['name']}" already exists but is turned off. '
                  'Turn it back on instead of adding it again.',
      );
    }
    return clean;
  }

  Category add(String name, {required int nowUtcMs}) {
    try {
      return _db.transaction(() {
        final clean = _validateName(name);
        final next =
            _db.raw
                    .select(
                      'SELECT COALESCE(MAX(sort_order), 0) + 10 AS n FROM categories;',
                    )
                    .first['n']
                as int;
        _db.raw.execute(
          '''INSERT INTO categories
             (name, name_key, is_active, requires_remark, sort_order,
              created_at_utc_ms, updated_at_utc_ms)
             VALUES (?, ?, 1, 0, ?, ?, ?);''',
          [clean, categoryNameKey(clean), next, nowUtcMs, nowUtcMs],
        );
        return byId(_db.raw.lastInsertRowId)!;
      });
    } on SqliteException catch (e) {
      throw mapSqliteError(e);
    }
  }

  Category rename(int id, String newName, {required int nowUtcMs}) {
    try {
      return _db.transaction(() {
        if (byId(id) == null) {
          throw const AppFailure(FailureKind.notFound, 'Category not found.');
        }
        final clean = _validateName(newName, excludingId: id);
        _db.raw.execute(
          'UPDATE categories SET name = ?, name_key = ?, updated_at_utc_ms = ? '
          'WHERE id = ?;',
          [clean, categoryNameKey(clean), nowUtcMs, id],
        );
        return byId(id)!;
      });
    } on SqliteException catch (e) {
      throw mapSqliteError(e);
    }
  }

  /// Deactivated categories stay on existing expenses and in reports, but
  /// cannot be chosen for new expenses.
  Category setActive(int id, bool active, {required int nowUtcMs}) {
    try {
      return _db.transaction(() {
        if (byId(id) == null) {
          throw const AppFailure(FailureKind.notFound, 'Category not found.');
        }
        _db.raw.execute(
          'UPDATE categories SET is_active = ?, updated_at_utc_ms = ? WHERE id = ?;',
          [active ? 1 : 0, nowUtcMs, id],
        );
        return byId(id)!;
      });
    } on SqliteException catch (e) {
      throw mapSqliteError(e);
    }
  }

  int usageCount(int id) =>
      _db.raw.select(
            'SELECT COUNT(*) AS n FROM expenses WHERE category_id = ?;',
            [id],
          ).first['n']
          as int;
}
