import 'package:sqlite3/sqlite3.dart';

import 'failures.dart';

/// Explicit, forward-only, non-destructive schema migrations.
///
/// Rules for future versions:
///  * Append a new step; never edit or remove a released step.
///  * Only additive changes (new tables, nullable/defaulted columns, new
///    indexes). If a table must be reshaped, copy into a new table inside
///    the same step and keep the data.
///  * Each step runs in its own transaction together with the
///    `user_version` bump, so a step is applied completely or not at all.
///  * There is no "drop and recreate" fallback in any build.
typedef Migration = void Function(Database db, int nowUtcMs);

final Map<int, Migration> migrations = {1: _v1};

int get latestSchemaVersion => migrations.keys.reduce((a, b) => a > b ? a : b);

/// Default categories, seeded exactly once by migration 1. Users may rename
/// or deactivate them afterwards; they are never re-seeded.
const seedCategories = <({String key, String name, bool requiresRemark})>[
  (key: 'petrol', name: 'Petrol', requiresRemark: false),
  (key: 'food', name: 'Food', requiresRemark: false),
  (key: 'labor', name: 'Labor', requiresRemark: false),
  (key: 'salik', name: 'Salik', requiresRemark: false),
  (key: 'carwash', name: 'Carwash', requiresRemark: false),
  (
    key: 'vehicle_maintenance',
    name: 'Vehicle Maintenance',
    requiresRemark: false,
  ),
  (key: 'car_parking_fee', name: 'Car Parking Fee', requiresRemark: false),
  (key: 'other', name: 'Other', requiresRemark: true),
];

void runMigrations(Database db, {required int nowUtcMs}) {
  final current = db.userVersion;
  final latest = latestSchemaVersion;
  if (current > latest) {
    throw const AppFailure(
      FailureKind.newerSchema,
      'This data was saved by a newer version of the app. Please install the '
      'latest version; your records have not been changed.',
    );
  }
  for (var v = current + 1; v <= latest; v++) {
    db.execute('BEGIN IMMEDIATE;');
    try {
      migrations[v]!(db, nowUtcMs);
      db.userVersion = v;
      db.execute('COMMIT;');
    } catch (_) {
      if (!db.autocommit) db.execute('ROLLBACK;');
      rethrow;
    }
  }
}

void _v1(Database db, int now) {
  db.execute('''
    CREATE TABLE categories (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL CHECK (length(trim(name)) > 0),
      name_key TEXT NOT NULL UNIQUE,
      is_active INTEGER NOT NULL DEFAULT 1 CHECK (is_active IN (0, 1)),
      requires_remark INTEGER NOT NULL DEFAULT 0 CHECK (requires_remark IN (0, 1)),
      sort_order INTEGER NOT NULL,
      seed_key TEXT UNIQUE,
      created_at_utc_ms INTEGER NOT NULL,
      updated_at_utc_ms INTEGER NOT NULL
    ) STRICT;
  ''');
  db.execute('''
    CREATE TABLE expenses (
      id TEXT PRIMARY KEY NOT NULL,
      category_id INTEGER NOT NULL REFERENCES categories(id) ON DELETE RESTRICT,
      category_label TEXT NOT NULL,
      amount_fils INTEGER NOT NULL
        CHECK (amount_fils > 0 AND amount_fils <= 99999999),
      remarks TEXT CHECK (remarks IS NULL OR length(remarks) BETWEEN 1 AND 2000),
      captured_at_utc_ms INTEGER NOT NULL,
      captured_tz_offset_min INTEGER NOT NULL,
      captured_tz_name TEXT NOT NULL,
      local_date TEXT NOT NULL
        CHECK (local_date GLOB '[0-9][0-9][0-9][0-9]-[0-1][0-9]-[0-3][0-9]'),
      local_time TEXT NOT NULL,
      created_at_utc_ms INTEGER NOT NULL,
      updated_at_utc_ms INTEGER NOT NULL
    ) STRICT;
  ''');
  // Reports filter by local_date range and sort newest first.
  db.execute(
    'CREATE INDEX idx_expenses_date ON expenses(local_date, captured_at_utc_ms);',
  );
  // Home list: newest first, keyset pagination.
  db.execute(
    'CREATE INDEX idx_expenses_captured ON expenses(captured_at_utc_ms, id);',
  );
  db.execute(
    'CREATE INDEX idx_expenses_category_date ON expenses(category_id, local_date);',
  );
  db.execute('''
    CREATE TABLE app_meta (
      key TEXT PRIMARY KEY NOT NULL,
      value TEXT NOT NULL
    ) STRICT;
  ''');

  final insert = db.prepare('''
    INSERT INTO categories
      (name, name_key, is_active, requires_remark, sort_order, seed_key,
       created_at_utc_ms, updated_at_utc_ms)
    VALUES (?, ?, 1, ?, ?, ?, ?, ?);
  ''');
  try {
    for (var i = 0; i < seedCategories.length; i++) {
      final s = seedCategories[i];
      insert.execute([
        s.name,
        s.name.toLowerCase(),
        s.requiresRemark ? 1 : 0,
        (i + 1) * 10,
        s.key,
        now,
        now,
      ]);
    }
  } finally {
    insert.close();
  }
  db.execute(
    "INSERT INTO app_meta (key, value) VALUES ('categories_seeded_at', ?);",
    ['$now'],
  );
}
