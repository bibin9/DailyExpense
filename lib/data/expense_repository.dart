import 'package:sqlite3/sqlite3.dart';

import '../core/capture.dart';
import '../core/local_date.dart';
import '../domain/models.dart';
import 'database.dart';
import 'failures.dart';

/// Cursor for newest-first paging without OFFSET scans.
class ExpenseCursor {
  const ExpenseCursor(this.capturedAtUtcMs, this.id);
  final int capturedAtUtcMs;
  final String id;
}

class ExpenseRepository {
  ExpenseRepository(this._db);

  final AppDatabase _db;

  static const _select = '''
    SELECT e.*, c.name AS current_name, c.is_active AS cat_active
    FROM expenses e LEFT JOIN categories c ON c.id = e.category_id
  ''';

  static Expense _map(Row r) => Expense(
    id: r['id'] as String,
    categoryId: r['category_id'] as int,
    categoryLabelSnapshot: r['category_label'] as String,
    currentCategoryName:
        (r['current_name'] as String?) ?? (r['category_label'] as String),
    categoryIsActive: r['cat_active'] == 1,
    amountFils: r['amount_fils'] as int,
    remarks: r['remarks'] as String?,
    captured: CaptureStamp(
      instantUtcMs: r['captured_at_utc_ms'] as int,
      offsetMinutes: r['captured_tz_offset_min'] as int,
      timeZoneName: r['captured_tz_name'] as String,
      localDate: LocalDate.parse(r['local_date'] as String),
      localTime: r['local_time'] as String,
    ),
    createdAtUtcMs: r['created_at_utc_ms'] as int,
    updatedAtUtcMs: r['updated_at_utc_ms'] as int,
  );

  Expense? byId(String id) {
    final rows = _db.raw.select('$_select WHERE e.id = ?;', [id]);
    return rows.isEmpty ? null : _map(rows.first);
  }

  ({String name, bool active})? _category(int id) {
    final rows = _db.raw.select(
      'SELECT name, is_active FROM categories WHERE id = ?;',
      [id],
    );
    if (rows.isEmpty) return null;
    return (
      name: rows.first['name'] as String,
      active: rows.first['is_active'] == 1,
    );
  }

  /// Inserts a new expense. Returns only after COMMIT succeeded.
  Expense insert(
    ExpenseDraft draft,
    CaptureStamp captured, {
    String? id,
    required int nowUtcMs,
  }) {
    final newId = id ?? newUuid();
    try {
      _db.transaction(() {
        final cat = _category(draft.categoryId);
        if (cat == null || !cat.active) {
          throw const AppFailure(
            FailureKind.categoryInactive,
            'That category is no longer available. Choose another.',
          );
        }
        _db.raw.execute(
          '''INSERT INTO expenses
             (id, category_id, category_label, amount_fils, remarks,
              captured_at_utc_ms, captured_tz_offset_min, captured_tz_name,
              local_date, local_time, created_at_utc_ms, updated_at_utc_ms)
             VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);''',
          [
            newId,
            draft.categoryId,
            cat.name,
            draft.amountFils,
            draft.remarks,
            captured.instantUtcMs,
            captured.offsetMinutes,
            captured.timeZoneName,
            captured.localDate.toIso(),
            captured.localTime,
            nowUtcMs,
            nowUtcMs,
          ],
        );
      });
    } on SqliteException catch (e) {
      throw mapSqliteError(e);
    }
    return byId(newId)!;
  }

  /// Updates category, amount and remarks. Capture date/time and creation
  /// time are never changed. Keeping a deactivated category is allowed;
  /// switching *to* a deactivated category is not.
  Expense update(String id, ExpenseDraft draft, {required int nowUtcMs}) {
    try {
      _db.transaction(() {
        final existing = byId(id);
        if (existing == null) {
          throw const AppFailure(
            FailureKind.notFound,
            'This expense no longer exists.',
          );
        }
        var label = existing.categoryLabelSnapshot;
        if (draft.categoryId != existing.categoryId) {
          final cat = _category(draft.categoryId);
          if (cat == null || !cat.active) {
            throw const AppFailure(
              FailureKind.categoryInactive,
              'That category is no longer available. Choose another.',
            );
          }
          label = cat.name;
        }
        _db.raw.execute(
          '''UPDATE expenses
             SET category_id = ?, category_label = ?, amount_fils = ?,
                 remarks = ?, updated_at_utc_ms = ?
             WHERE id = ?;''',
          [
            draft.categoryId,
            label,
            draft.amountFils,
            draft.remarks,
            nowUtcMs,
            id,
          ],
        );
      });
    } on SqliteException catch (e) {
      throw mapSqliteError(e);
    }
    return byId(id)!;
  }

  /// Permanent deletion (no recycle bin in this version).
  bool delete(String id) {
    try {
      return _db.transaction(() {
        _db.raw.execute('DELETE FROM expenses WHERE id = ?;', [id]);
        return _db.raw.updatedRows == 1;
      });
    } on SqliteException catch (e) {
      throw mapSqliteError(e);
    }
  }

  /// Newest first, [limit] rows after [after].
  List<Expense> recent({int limit = 30, ExpenseCursor? after}) {
    final rows = after == null
        ? _db.raw.select(
            '$_select ORDER BY e.captured_at_utc_ms DESC, e.id DESC LIMIT ?;',
            [limit],
          )
        : _db.raw.select(
            '''$_select
               WHERE (e.captured_at_utc_ms, e.id) < (?, ?)
               ORDER BY e.captured_at_utc_ms DESC, e.id DESC LIMIT ?;''',
            // Row-value comparison lets SQLite walk idx_expenses_captured
            // directly (an OR here forced a full scan on every page).
            [after.capturedAtUtcMs, after.id, limit],
          );
    return rows.map(_map).toList();
  }

  DaySummary summaryFor(LocalDate date) {
    final r = _db.raw.select(
      'SELECT COUNT(*) AS n, COALESCE(SUM(amount_fils), 0) AS t '
      'FROM expenses WHERE local_date = ?;',
      [date.toIso()],
    ).first;
    return DaySummary(count: r['n'] as int, totalFils: r['t'] as int);
  }

  /// Entries, count, total and per-category subtotals for an inclusive
  /// local-date range. Totals are computed by SQLite in 64-bit integers.
  ReportData report(ReportPeriod period) {
    final args = [period.start.toIso(), period.end.toIso()];
    final entries = _db.raw
        .select('''$_select
             WHERE e.local_date BETWEEN ? AND ?
             ORDER BY e.captured_at_utc_ms DESC, e.id DESC;''', args)
        .map(_map)
        .toList();
    final groups = _db.raw.select('''
      SELECT e.category_id AS id,
             COALESCE(c.name, MAX(e.category_label)) AS name,
             COALESCE(c.is_active, 0) AS active,
             COUNT(*) AS n, SUM(e.amount_fils) AS t
      FROM expenses e LEFT JOIN categories c ON c.id = e.category_id
      WHERE e.local_date BETWEEN ? AND ?
      GROUP BY e.category_id
      ORDER BY t DESC, name;
    ''', args);
    final byCategory = groups
        .map(
          (g) => CategoryTotal(
            categoryId: g['id'] as int,
            name: g['name'] as String,
            isActive: g['active'] == 1,
            count: g['n'] as int,
            totalFils: g['t'] as int,
          ),
        )
        .toList();
    return ReportData(
      period: period,
      entries: entries,
      count: byCategory.fold(0, (s, c) => s + c.count),
      totalFils: byCategory.fold(0, (s, c) => s + c.totalFils),
      byCategory: byCategory,
    );
  }

  int count() =>
      _db.raw.select('SELECT COUNT(*) AS n FROM expenses;').first['n'] as int;
}
